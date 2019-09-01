;;; cal-in-taiwan.el --- Chinese localization, lunar/horoscope/zodiac info and more...

;; Copyright (C) 2006-2013, 2015 William Xu
;; 2019-09 imper0502 修改 via opencc

;; Author: William Xu <william.xwl@gmail.com>
;; Version: 2.6b
;; Url: https://github.com/xwl/cal-in-taiwan
;; Package-Requires: ((cl-lib "0.5"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
;; MA 02110-1301, USA.

;;; Commentary:

;; This extension mainly adds the following extra features:
;;   - Chinese localizations
;;   - Display holiday, lunar, horoscope, zodiac, solar term info on mode line
;;   - Define holidays using `holiday-lunar', `holiday-solar-term'
;;   - Highlight holidays based on different priorities
;;   - Add `cal-in-taiwan-chinese-holidays', `cal-in-taiwan-japanese-holidays'.
;;   - custom week diary(like weeks in school)
;;
;; To use, add something like the following to your .emacs:
;;     (require 'cal-in-taiwan)
;;     (setq mark-holidays-in-calendar t)
;;     (setq cal-in-taiwan-important-holidays cal-in-taiwan-chinese-holidays)
;;     (setq cal-in-taiwan-general-holidays '((holiday-lunar 1 15 "元宵節")))
;;     (setq calendar-holidays
;;           (append cal-in-taiwan-important-holidays
;;                   cal-in-taiwan-general-holidays
;;                   other-holidays))
;;
;; Note: for emacs22, please use version 1.1.

;;; History

;; This is an early derived work from `chinese-calendar.el' written by
;; Charles Wang <charleswang@peoplemail.com.cn>.

;;; Note:

;; - Display week day(the first line of each month) in chinese properly
;;   It is a bit difficult to do nice alignment since it depends on the font
;;   size of chinese characters and numbers. But some manages to do it:
;;     https://github.com/xwl/cal-in-taiwan/issues/3

;;; Code:

(require 'calendar)
(require 'holidays)
(require 'cal-china)
(require 'cl-lib)

;;; Variables

(defconst cal-in-taiwan-dir (if load-file-name
                              (file-name-directory load-file-name)
                            ""))

;; Bound in calendar-generate.
(defvar displayed-month)
(defvar displayed-year)

(defconst cal-in-taiwan-celestial-stem
  ["甲" "乙" "丙" "丁" "戊" "己" "庚" "辛" "壬" "癸"])

(defconst cal-in-taiwan-terrestrial-branch
  ["子" "醜" "寅" "卯" "辰" "巳" "午" "未" "申" "酉" "戌" "亥"])

(defconst cal-in-taiwan-days
  ["日" "一" "二" "三" "四" "五" "六"])

(defconst cal-in-taiwan-month-name
  ["正月" "二月" "三月" "四月" "五月" "六月" "七月" "八月" "九月" "十月" "冬月" "臘月"])

(defconst cal-in-taiwan-day-name
  ["初一" "初二" "初三" "初四" "初五" "初六" "初七" "初八" "初九" "初十"
   "十一" "十二" "十三" "十四" "十五" "十六" "十七" "十八" "十九"  "廿"
   "廿一" "廿二" "廿三" "廿四" "廿五" "廿六" "廿七" "廿八" "廿九" "三十"
   "卅一" "卅二" "卅三" "卅四" "卅五" "卅六" "卅七" "卅八" "卅九" "卌"])

(defvar chinese-date-diary-pattern
  `((year "年" month "月" day "日" " 星期[" ,(mapconcat 'identity cal-in-taiwan-days "") "]")
    ,@(if (> emacs-major-version 22)
          diary-iso-date-forms
        '((month "[-/]" day "[^-/0-9]")
          (year "[-/]" month "[-/]" day "[^0-9]")
          (monthname "-" day "[^-0-9]")
          (year "-" monthname "-" day "[^0-9]")
          (dayname "\\W")))))

(defconst cal-in-taiwan-horoscope-name
  '(((3  21) (4  19) "牡羊")
    ((4  20) (5  20) "金牛")
    ((5  21) (6  21) "雙子")
    ((6  22) (7  22) "巨蟹")
    ((7  23) (8  22) "獅子")
    ((8  23) (9  22) "處女")
    ((9  23) (10 23) "天秤")
    ((10 24) (11 22) "天蠍")
    ((11 23) (12 21) "射手")
    ((12 22) (1  19) "摩羯")
    ((1  20) (2  18) "水瓶")
    ((2  19) (3  20) "雙魚")))

(defconst cal-in-taiwan-zodiac-name
  ["鼠" "牛" "虎" "兔" "龍" "蛇" "馬" "羊" "猴" "雞" "狗" "豬"]
  "The zodiac(生肖) when you were born.")

;; for ref, http://www.geocities.com/calshing/chinesecalendar.htm
(defconst cal-in-taiwan-solar-term-name
  ["小寒" "大寒" "立春" "雨水" "驚蟄" "春分"
   "清明" "穀雨" "立夏" "小滿" "芒種" "夏至"
   "小暑" "大暑" "立秋" "處暑" "白露" "秋分"
   "寒露" "霜降" "立冬" "小雪" "大雪" "冬至"]
  "24 solar terms(節氣, in chinese).
\"小寒\" is the first solar term in a new year. e.g., 2007-01-06.
There is a short poem for remembering,

    春雨驚春清谷天，夏滿芒夏暑相連，
    秋處露秋寒霜降，冬雪雪冬小大寒。")

(defconst cal-in-taiwan-japanese-holidays
  '((holiday-fixed 1 1 "元旦")
    (holiday-fixed 1 2 "公務員法定休息日")
    (holiday-fixed 1 3 "公務員法定休息日")
    (holiday-fixed 1 4 "公務員法定休息日")
    (holiday-float 1 1 1 "成人の日")
    (holiday-fixed 2 11 "建國記念の日")
    (holiday-solar-term "春分" "春分の日")
    (holiday-fixed 4 29 "みどりの日")
    (holiday-fixed 5 3 "憲法記念日")
    (holiday-fixed 5 4 "國民の休日")
    (holiday-fixed 5 5 "こどもの日")
    (holiday-fixed 7 20 "海の日")
    (holiday-fixed 9 15 "敬老の日")
    (holiday-solar-term "秋分" "秋分の日")
    (holiday-float 10 1 0 "體育の日")
    (holiday-fixed 11 3 "文化の日")
    (holiday-fixed 11 23 "勤労感謝の日")
    (holiday-fixed 12 23 "天皇誕生日")
    (holiday-fixed 12 28 "公務員法定休息日")
    (holiday-fixed 12 29 "公務員法定休息日")
    (holiday-fixed 12 30 "公務員法定休息日")
    (holiday-fixed 12 31 "公務員法定休息日"))
  "Pre-defined japanese public holidays.
You can add this to your `calendar-holidays'.")

(defconst cal-in-taiwan-chinese-holidays
  '((holiday-fixed 1 1 "元旦")
    (holiday-lunar 12 30 "除夕" 0)
    (holiday-lunar 1 1 "春節" 0)
    (holiday-solar-term "清明" "清明節")
    (holiday-fixed 5 1 "勞動節")
    (holiday-lunar 5 5 "端午節" 0)
    (holiday-lunar 8 15 "中秋節" 0)
    (holiday-fixed 10 10 "國慶日"))
  "Pre-defined chinese public holidays.
You can add this to your `calendar-holidays'.")

;;; Interfaces

(defgroup cal-in-taiwan nil
  "Chinese calendar extentions and more."
  :group 'calendar)

(defcustom cal-in-taiwan-important-holidays '()
  "Highlighted by `cal-in-taiwan-important-holiday-face'."
  :type 'symbol
  :group 'cal-in-taiwan)

(defcustom cal-in-taiwan-general-holidays '()
  "Highlighted by `cal-in-taiwan-general-holiday-face'."
  :type 'symbol
  :group 'cal-in-taiwan)

(defface cal-in-taiwan-important-holiday-face
  '((((class color) (background light))
     :background "red")
    (((class color) (background dark))
     :background "red")
    (t
     :inverse-video t))
  "Face for indicating `cal-in-taiwan-important-holidays'."
  :group 'cal-in-taiwan)

(defface cal-in-taiwan-general-holiday-face
  '((((class color) (background light))
     :background "green")
    (((class color) (background dark))
     :background "green")
    (t
     :inverse-video t))
  "Face for indicating `cal-in-taiwan-general-holidays'."
  :group 'cal-in-taiwan)

(defcustom cal-in-taiwan-custom-week-start-date '()
  "The month and day of first Monday in your custom week diary.

e.g., '(9 20) means from every year, Sep 20th will be defined as
the first week.  This could be useful in some circumstances, such
as schools, where people may use some specific school diary."
  :type 'symbol
  :group 'cal-in-taiwan)

(defcustom cal-in-taiwan-force-chinese-week-day nil
  "Force using chinese week day, even though it may not align nicely.

Default is nil. The chinese week day will be enabled automatically if
the package 'cnfonts (old name: 'chinese-fonts-setup) is loaded."
  :type 'boolean
  :group 'cal-in-taiwan)

;;;###autoload
(defun cal-in-taiwan-birthday-from-chinese (lunar-month lunar-day)
  "Return next birthday date in Gregorian form.

LUNAR-MONTH and LUNAR-DAY are date number used in chinese lunar
calendar."
  (interactive "nlunar month: \nnlunar day: ")
  (let* ((current-chinese-date (calendar-chinese-from-absolute
                                (calendar-absolute-from-gregorian
                                 (calendar-current-date))))
         (cycle (car current-chinese-date))
         (year (cadr current-chinese-date))
         (birthday-gregorian-full
          (cal-in-taiwan-birthday-from-chinese-1
           cycle year lunar-month lunar-day)))
    ;; If it is before current date, calculate next year.
    (when (calendar-date-compare (list birthday-gregorian-full)
                                 (list (calendar-current-date)))
      (setq birthday-gregorian-full
            (cal-in-taiwan-birthday-from-chinese-1
             cycle (1+ year) lunar-month lunar-day)))
    (message "Your next birthday in gregorian is on %s"
             (calendar-date-string birthday-gregorian-full))))

(defun cal-in-taiwan-birthday-from-chinese-1 (cycle year lunar-month lunar-day)
  (calendar-gregorian-from-absolute
   (calendar-chinese-to-absolute
    (list cycle year lunar-month lunar-day))))

;;;###autoload
(defun holiday-lunar (lunar-month lunar-day string &optional num)
  "Like `holiday-fixed', but with LUNAR-MONTH and LUNAR-DAY.

When there are multiple days(like Run Yue or 閏月, e.g.,
2006-08-30, which is 07-07 in lunar calendar, the chinese
valentine's day), we use NUM to define which day(s) as
holidays. The rules are:

NUM = 0, only the earlier day.
NUM = 1, only the later day.
NUM with other values(default), all days(maybe one or two).

emacs23 introduces a similar `holiday-chinese', a quick test
shows that it does not recognize Run Yue at all."
  (unless (integerp num)
    (setq num 2))
  (let ((holiday (holiday-lunar-1 lunar-month lunar-day string num)))
    (when (and (= lunar-day 30)         ; Some months only have 29 days.
               (equal (holiday-lunar-1 (if (= lunar-month 12) 1 (1+ lunar-month))
                                       1 string num)
                      holiday))
      (setq holiday (holiday-lunar-1 lunar-month (1- lunar-day) string num)))
    holiday))

(defun holiday-lunar-1 (lunar-month lunar-day string &optional num)
  (let* ((cn-years (calendar-chinese-year ; calendar-chinese-year counts from 12 for last year
                    (if (and (eq displayed-month 12) (eq lunar-month 12))
                        (1+ displayed-year)
                      displayed-year)))
         (ret (holiday-lunar-2 (assoc lunar-month cn-years) lunar-day string)))
    (when (and (> (length cn-years) 12) (not (zerop num)))
      (let ((run-yue '())
            (years cn-years)
            (i '()))
        (while years
          (setq i (car years)
                years (cdr years))
          (unless (integerp (car i))
            (setq run-yue i)
            (setq years nil)))
        (when (= lunar-month (floor (car run-yue)))
          (setq ret (append ret (holiday-lunar-2
                                 run-yue lunar-day string))))))
    (cond ((= num 0)
           (when (car ret) (list (car ret))))
          ((= num 1)
           (if (cadr ret) (list (cadr ret)) ret))
          (t
           ret))))

(defun holiday-lunar-2 (run-yue lunar-day string)
  (let* ((date (calendar-gregorian-from-absolute
                (+ (cadr run-yue) (1- lunar-day))))
         (holiday (holiday-fixed (car date) (cadr date) string)))
    ;; Same year?
    (when (and holiday (= (nth 2 (caar holiday)) (nth 2 date)))
      holiday)))

;;;###autoload
(defun holiday-solar-term (solar-term str)
  "A holiday(STR) on SOLAR-TERM day.
See `cal-in-taiwan-solar-term-name' for a list of solar term names ."
  (cal-in-taiwan-sync-solar-term displayed-year)
  (let ((terms cal-in-taiwan-solar-term-alist)
        i date)
    (while terms
      (setq i (car terms)
            terms (cdr terms))
      (when (string= (cdr i) solar-term)
        (let ((m (caar i))
              (y (cl-caddar i)))
          ;; displayed-year, displayed-month is accurate for the centered month
          ;; only. Cross year view: '(11 12 1), '(12 1 2)
          (when (or (and (cal-in-taiwan-cross-year-view-p)
                         (or (and (= displayed-month 12)
                                  (= m 1)
                                  (= y (1+ displayed-year)))
                             (and (= displayed-month 1)
                                  (= m 12)
                                  (= y (1- displayed-year)))))
                    (= y displayed-year))
            (setq terms '()
                  date (car i))))))
    (holiday-fixed (car date) (cadr date) str)))

(defun cal-in-taiwan-calendar-display-form (date)
  (if (equal date '(0 0 0))
      ""
    (format "%04d年%02d月%02d日 %s"
            (calendar-extract-year date)
            (calendar-extract-month date)
            (calendar-extract-day date)
            (cal-in-taiwan-day-name date))))

(defun cal-in-taiwan-chinese-date-string (date)
  (let* ((cn-date (calendar-chinese-from-absolute
                   (calendar-absolute-from-gregorian date)))
         (cn-year  (cadr   cn-date))
         (cn-month (cl-caddr  cn-date))
         (cn-day   (cl-cadddr cn-date)))
    (format "%s%s年%s%s%s(%s)%s"
            (calendar-chinese-sexagesimal-name cn-year)
            (aref cal-in-taiwan-zodiac-name (% (1- cn-year) 12))
            (aref cal-in-taiwan-month-name (1-  (floor cn-month)))
            (if (integerp cn-month) "" "(閏月)")
            (aref cal-in-taiwan-day-name (1- cn-day))
            (cal-in-taiwan-get-horoscope (car date) (cadr date))
            (cal-in-taiwan-get-solar-term date))))

(defun cal-in-taiwan-setup ()
  (setq calendar-date-display-form
	'((cal-in-taiwan-calendar-display-form
           (mapcar (lambda (el) (string-to-number el))
                   (list month day year)))))

  (setq diary-date-forms chinese-date-diary-pattern)

  (setq calendar-chinese-celestial-stem cal-in-taiwan-celestial-stem
        calendar-chinese-terrestrial-branch cal-in-taiwan-terrestrial-branch)

  (setq calendar-month-header '(propertize (format "%d年%2d月" year month)
                                           'font-lock-face
                                           'calendar-month-header))

  (if cal-in-taiwan-force-chinese-week-day
      (setq calendar-day-header-array cal-in-taiwan-days)

    (eval-after-load 'chinese-fonts-setup ; older name of cnfonts, to be removed
      '(progn
         (setq calendar-day-header-array cal-in-taiwan-days)
         ))

    (eval-after-load 'cnfonts
      '(progn
         (setq calendar-day-header-array cal-in-taiwan-days)
         )))

  (setq calendar-mode-line-format
        (list
         (calendar-mode-line-entry 'calendar-scroll-right "previous month" "<")
         "Calendar"

         '(cal-in-taiwan-get-holiday date)

         '(concat " " (calendar-date-string date t)
                  (format " 第%d週"
                          (funcall (if cal-in-taiwan-custom-week-start-date
                                       'cal-in-taiwan-custom-week-of-date
                                     'cal-in-taiwan-week-of-date)
                                   date)))

         '(cal-in-taiwan-chinese-date-string date)

         ;; (concat
         ;;  (calendar-mode-line-entry 'calendar-goto-info-node "read Info on Calendar"
         ;;                            nil "info")
         ;;  " / "
         ;;  (calendar-mode-line-entry 'calendar-other-month "choose another month"
         ;;                            nil "other")
         ;;  " / "
         ;;  (calendar-mode-line-entry 'calendar-goto-today "go to today's date"
         ;;                            nil "today"))

         (calendar-mode-line-entry 'calendar-scroll-left "next month" ">")))

  (add-hook 'calendar-move-hook 'calendar-update-mode-line)
  (add-hook 'calendar-initial-window-hook 'calendar-update-mode-line)

  (add-hook 'calendar-mode-hook
            (lambda ()
              (set (make-local-variable 'font-lock-defaults)
                   ;; chinese month and year
                   '((("[0-9]+年\\ *[0-9]+月" . font-lock-function-name-face)) t))
              ))

  (advice-add 'calendar-mark-holidays :around 'cal-in-taiwan-mark-holidays)
  (advice-add 'mouse-set-point :after 'cal-in-taiwan-mouse-set-point)
  )


;;; Implementations

(defun cal-in-taiwan-day-name (date)
  "Chinese day name in a week, like `星期一'."
  (concat "星期" (aref cal-in-taiwan-days (calendar-day-of-week date))))

(defun cal-in-taiwan-day-short-name (num)
  "Short chinese day name in a week, like `一'. NUM is from 0..6
in a week."
  (aref cal-in-taiwan-days num))

(defun cal-in-taiwan-get-horoscope (month day)
  "Return horoscope(星座) on MONTH(1-12) DAY(1-31)."
  (catch 'return
    (mapc
     (lambda (el)
       (let ((start (car el))
             (end (cadr el)))
         (when (or (and (= month (car start)) (>= day (cadr start)))
                   (and (= month (car end)) (<= day (cadr end))))
           (throw 'return (cl-caddr el)))))
     cal-in-taiwan-horoscope-name)))

(defun holiday-chinese-new-year ()
  "Date of Chinese New Year."
  (let ((m displayed-month)
        (y displayed-year))
    (calendar-increment-month m y 1)
    (if (< m 5)
        (let ((chinese-new-year
               (calendar-gregorian-from-absolute
                (cadr (assoc 1 (calendar-chinese-year y))))))
          (if (calendar-date-is-visible-p chinese-new-year)
	      `((,chinese-new-year
                 ,(format "%s年春節"
                          (calendar-chinese-sexagesimal-name
                           (+ y 57))))))))))

(defun cal-in-taiwan-get-solar-term (date)
  (let ((year (calendar-extract-year date)))
    (cal-in-taiwan-sync-solar-term year)
    (or (cdr (assoc date cal-in-taiwan-solar-term-alist)) "")))

(defun cal-in-taiwan-solar-term-alist-new (year)
  "Return a solar-term alist for YEAR."
  ;; use cached values (china time zone +0800)
  (let ((cached-jieqi-file (expand-file-name (concat cal-in-taiwan-dir "/jieqi.txt"))))
    (if (and (> year 1900)
             (< year 2101)
             (file-exists-p cached-jieqi-file))
        (let ((solar-term-alist '())
              (year (number-to-string year)))
          (with-temp-buffer
            (insert-file-contents cached-jieqi-file)
            (goto-char (point-min))
            (while (search-forward year nil t 1)
              (let* ((str (buffer-substring (line-beginning-position) (line-end-position)))
                     (lst (split-string str))
                     (jieqi (nth 0 lst))
                     (y (string-to-number (nth 1 lst)))
                     (m (string-to-number (nth 2 lst)))
                     (d (string-to-number (nth 3 lst))))
                (setq solar-term-alist (cons (cons (list m d y) jieqi)
                                             solar-term-alist)))))
          solar-term-alist)
      ;; calculation may have one day difference.
      (cl-loop for i from 0 upto 23

             for date = (cal-in-taiwan-next-solar-term `(1 1 ,year))
             then (setq date (cal-in-taiwan-next-solar-term date))

             with solar-term-alist = '()

             collect (cons date (aref cal-in-taiwan-solar-term-name i))
             into solar-term-alist

             finally return solar-term-alist))))

(defun cal-in-taiwan-gregorian-from-astro (a)
  (calendar-gregorian-from-absolute
   (floor (calendar-astro-to-absolute a))))

(defun cal-in-taiwan-astro-from-gregorian (g)
  (calendar-astro-from-absolute
   (calendar-absolute-from-gregorian g)))

(defun cal-in-taiwan-next-solar-term (date)
  "Return next solar term's data after DATE.
Each solar term is separated by 15 longtitude degrees or so, plus an
extra day appended."
  (cal-in-taiwan-gregorian-from-astro
   (solar-date-next-longitude
    (calendar-astro-from-absolute
     (1+ (calendar-absolute-from-gregorian date))) 15)))

(defun cal-in-taiwan-get-holiday (date)
  (when (and (boundp 'displayed-month)
             (boundp 'displayed-year))
    (let ((holidays (calendar-holiday-list))
          (str ""))
      (dolist (i holidays)
        (when (equal (car i) date)
          (setq str (concat str " " (cadr i)))))
      str)))

;; cached solar terms for two neighbour years at most.
(defvar cal-in-taiwan-solar-term-alist nil) ; e.g., '(((1 20 2008) "春分") ...)
(defvar cal-in-taiwan-solar-term-years nil)

(defun cal-in-taiwan-sync-solar-term (year)
  "Sync `cal-in-taiwan-solar-term-alist' and `cal-in-taiwan-solar-term-years' to YEAR."
  (cond ((or (not cal-in-taiwan-solar-term-years)
             ;; TODO: Seems calendar-update-mode-line is called too early in
             ;; calendar-mode.
             (not (boundp 'displayed-year))
             (not (boundp 'displayed-month)))
         (setq cal-in-taiwan-solar-term-alist
               (cal-in-taiwan-solar-term-alist-new year))
         (setq cal-in-taiwan-solar-term-years (list year)))
        ((not (memq year cal-in-taiwan-solar-term-years))
         (setq cal-in-taiwan-solar-term-alist
               (append
                (cl-remove-if-not (lambda (i) (eq (cl-caddar i) displayed-year))
                                  cal-in-taiwan-solar-term-alist)
                (cal-in-taiwan-solar-term-alist-new year)))
         (setq cal-in-taiwan-solar-term-years
               (cons year (cl-remove-if-not (lambda (i) (eq i displayed-year))
                                            cal-in-taiwan-solar-term-years))))))

;; When months are: '(11 12 1), '(12 1 2)
(defun cal-in-taiwan-cross-year-view-p ()
  (or (= displayed-month 12) (= displayed-month 1)))

;; ,----
;; | week
;; `----

(defun cal-in-taiwan-week-of-date (date)
  "Get week number from DATE."
  (car (calendar-iso-from-absolute (calendar-absolute-from-gregorian date))))

(defun cal-in-taiwan-custom-week-of-date (date)
  "Similar to `cal-in-taiwan-week-of-date' but starting from `cal-in-taiwan-custom-week-start-date'."
  (let* ((y (calendar-extract-year  date))
         (m (calendar-extract-month date))
         (d (calendar-extract-day   date))
         (start-date `(,@cal-in-taiwan-custom-week-start-date ,y))
         (start-month (calendar-extract-month start-date))
         (start-day   (calendar-extract-day start-date)))

    (when (or (< m start-month)
              (and (= m start-month) (< d start-day)))
      (setq start-date (list (car start-date) (cadr start-date) (1- y))))

    (1+ (/ (cal-in-taiwan-days-diff date start-date) 7))))

(defun cal-in-taiwan-days-diff (date1 date2)
  "date1 - date2 = ?"
  (apply '- (mapcar 'calendar-absolute-from-gregorian (list date1 date2))))


;;; Modifications to Standard Functions

;; These functions(from calendar.el, cal-china.el) have been modified
;; for localization.

(defun calendar-chinese-sexagesimal-name (n)
  "The N-th name of the Chinese sexagesimal cycle.
N congruent to 1 gives the first name, N congruent to 2 gives the second name,
..., N congruent to 60 gives the sixtieth name."
  ;; Change "%s-%s" to "%s%s", since adding the extra `-' between two Chinese
  ;; characters looks stupid.
  (format "%s%s"
          (aref calendar-chinese-celestial-stem (% (1- n) 10))
          (aref calendar-chinese-terrestrial-branch (% (1- n) 12))))

(defun cal-in-taiwan-remove-exising-overlays (beg end &rest args)
  (remove-overlays beg end))

(defun cal-in-taiwan-mark-holidays (orig-fun &rest args)
  "Mark prioritized holidays with different colors."
  (apply orig-fun args)

  (advice-add 'make-overlay :before 'cal-in-taiwan-remove-exising-overlays)
  (let ((calendar-holiday-marker 'cal-in-taiwan-general-holiday-face)
        (calendar-holidays cal-in-taiwan-general-holidays))
    (apply orig-fun args))
  (let ((calendar-holiday-marker 'cal-in-taiwan-important-holiday-face)
        (calendar-holidays cal-in-taiwan-important-holidays))
    (apply orig-fun args))
  (advice-remove 'make-overlay 'cal-in-taiwan-remove-exising-overlays))

(defun cal-in-taiwan-mouse-set-point (after &rest args)
    (when (eq major-mode 'calendar-mode)
      (calendar-update-mode-line)))


;; setup
(cal-in-taiwan-setup)

(provide 'cal-in-taiwan)

;;; Local Variables: ***
;;; coding: utf-8 ***
;;; End: ***

;;; cal-in-taiwan.el ends here
