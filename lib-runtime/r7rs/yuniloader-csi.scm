(use r7rs)

(import (scheme base) 
        (scheme load)
        (scheme read)
        (scheme write)
        (scheme cxr)
        (scheme file)
        (scheme process-context))

;; Currently, only for picrin

(define ERRPORT current-error-port)
(define (PCK . obj)
  (if #t  ;; %verbose
    (begin
      (if #t ;; (not DEBUGGING)
        (begin
          (display "-> " (ERRPORT))
          (for-each (lambda (e)
                      (write e (ERRPORT))
                      (display " " (ERRPORT)))
                    obj)
          (newline (ERRPORT)))))))


(define (run filename)
  (define import-dirs
    '("lib-stub/chicken" "lib-runtime/r7rs"))

  (define (make-library-path base nam)
    ;(PCK 'make-library-path: base nam)
    (if (pair? nam)
      (make-library-path (string-append (string-append base "/") 
                                        (symbol->string (car nam))) 
                         (cdr nam))
      (string-append base ".scm")))
  (define loaded-libraries '())
  (define (library-loaded? nam)
    (define (itr rest)
      (and (pair? rest)
           (or (equal? nam (caar rest))
               (itr (cdr rest)))))
    (itr loaded-libraries))
  (define (mark-as-loaded! nam filename)
    (set! loaded-libraries (cons (cons nam filename) loaded-libraries)))
  (define (builtin-library? nam)
    (and (pair? nam)
         (let ((prefix (car nam)))
          (case prefix
            ((scheme chicken matchable) #t)
            ((srfi) (number? (cadr nam)))
            (else #f)))))

  (define (library-name->path name)
    (define (itr rest)
      (if (pair? rest)
        (or (let ((name (make-library-path (car rest) name)))
              (PCK 'TRYING: name)
              (and (file-exists? name)
                   name))
            (itr (cdr rest)))
        (error "library-name->path: Cannot find library for" name)))
    (PCK 'LOOKUP: name)
    (itr import-dirs))

  (define (realize-library name)
    (unless (or (builtin-library? name) (library-loaded? name))
      (let ((path (library-name->path name)))
       (load-library-file path)
       (mark-as-loaded! name path))))

  (define (process-import-clause lis)
    (cond ((pair? lis)
           (if (or (eq? (car lis) 'only)
                   (eq? (car lis) 'except)
                   (eq? (car lis) 'rename))
             (process-import-clause (cadr lis))
             (realize-library lis)))
          (else (error "process-import-clause: Wrong format" lis))))

  (define (load-library-file path)
    (call-with-input-file 
      path
      (lambda (p)
        (let ((x (read p)))
         (PCK 'READING: path)
         (unless (and (pair? x) (eq? (car x) 'define-library))
           (error "load-library-file: Malformed library" path))
         (let ((import-clause (cdr (cadddr x))))
          (PCK 'PROC: import-clause)
          (for-each process-import-clause import-clause))))))

  (PCK 'RUN: filename)

  (unless (and (string? filename) (file-exists? filename))
    (error "run: File not found" filename))

  ;; Lookup for import clause
  (call-with-input-file
    filename
    (lambda (p)
      ;; Read (import ...)
      (let ((x (read p)))
       (unless (and (pair? x) (eq? (car x) 'import))
         (error "run: Malformed program" filename))
       (for-each process-import-clause (cdr x)))))

  ;; Do actual load process in reverse order
  (let ((files (map cdr (reverse loaded-libraries))))
   (for-each (lambda (filename) 
               (PCK 'LOADING: filename)
               (load filename)) files))

  (load filename))

(define ARG (cdr (command-line)))

;(write (list 'ARG: ARG))(newline)

(with-exception-handler
  (lambda (e) (PCK 'EXCEPTION: 
                   (error-object-message e) 
                   (error-object-irritants e))
    (exit -1))
  (lambda () (run (cadr ARG))))

