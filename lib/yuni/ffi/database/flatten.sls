(library (yuni ffi database flatten)
         (export
           database->flatten/functions
           database->flatten/constants
           ;; database-merge-flatten/constants
           )
         (import (yuni scheme)
                 (yuni base match)

                 ;; Database
                 (yuni ffi database root)
                 (yuni ffi database libinfo)
                 (yuni ffi database types)
                 (yuni ffi database layouts)
                 (yuni ffi database exports)
                 (yuni ffi database functions)
                 
                 ;; FIXME: R6RS libs
                 (only (rnrs) 
                       ;; SRFI-1
                       filter
                       ;; Hashtable
                       hashtable-keys
                       make-eq-hashtable
                       hashtable-set!
                       hashtable-ref))

;; 
;; Flatten: convert database into s-exp(lists)
;;
;; Functions DB::
;;    ("db name" (<entry> ...))
;;    
;;  entry ::=
;;      ("label" (<arg-c-return> ...) (<arg> ...) . attr)
;;
;;    arg ::=
;;      (<type> "label" "c type string" . attr)
;;      ### label may be non-string;
;;      ###  #f = return-value
;;      ###  symbol = special-use (forward-1 funcptr)
;;
;;    type ::= signed | unsigned | real | blob | pointer
;;
;; Constants DB::
;;    ("db name" (<entry> ...))
;;    
;;    entry ::= 
;;      (constant        "label" <type> value sizeof <if> ...)
;;      (layout          "label" <type> <c-instance-type> sizeof <if> ...)
;;      (aggregate-entry "label" <type> "parent label" "C ref name"
;;                       sizeof offset <if> ...)
;;
;;           type ::= signed | unsigned | real | blob | pointer
;;c-instance-type ::= value | c-struct | c-enum | c-union
;;             if ::= (ifdef "C MACRO symbol")
;;

;;; Type resolver
(define (make-resolve-type types)
  (define type-ht (make-eq-hashtable))
  (define (cache-types!)
    (define types-stdc (append (types-entries (gen-types-stdc))
                               (types-entries (gen-types-stdint))))
    (define (add-cache! sym basetype)
      (hashtable-set! type-ht sym (basetype->ctype basetype)))
    ;; Scan for types and cache type => c-type map
    ;; Import c standard type sets
    (for-each (lambda (e) (add-cache! (type-name e) (type-basetype e)))
              types-stdc)
    ;; FIXME: Allow different type sets here?
    ;; Import defined types
    (for-each (lambda (e) (add-cache! (type-name e) (type-basetype e)))
              types))

  (define (resolve-type sym)
    ;; Resolve type to c-type(signed / unsigned / real / blob)
    (or (hashtable-ref type-ht sym #f)
        (error "No matching type found" sym)))
  (cache-types!)
  resolve-type)

(define (make-resolve-cterms types)
  (define type-ht (make-eq-hashtable))
  (define (cache! sym x)
    (hashtable-set! type-ht sym x))

  (define (type-cterm type) ;; Return type itself if we cannot resolve cterm
    (or (type-c-name type)
        ;; Use typename itself if it was not a pointer-base and c-whatever
        (and (not (type-pointer-base type))
             ;; We allow c-enum later though
             (not (type-c-enum? type))
             (not (type-c-struct? type))
             (not (type-c-union? type))
             ;; Use the name of the type then
             (symbol->string (type-name type)))
        (and (type-c-enum? type)
             (string-append "enum " (symbol->string (type-name type))))
        (and (type-c-union? type)
             (string-append "union " (symbol->string (type-name type))))
        (and (type-c-struct? type)
             (string-append "struct " (symbol->string (type-name type))))

        ;; Fallback. Use type itself
        type))

  (define (resolve-pointer-base!)
    (define (notyet) (filter (lambda (e) (not (string? 
                                                (hashtable-ref type-ht e)))) 
                             (vector->list (hashtable-keys type-ht))))
    (define (proc name)
      (let ((t (hashtable-ref type-ht name #f)))
       (let* ((base (type-pointer-base t))
              (x (hashtable-ref type-ht base #f)))
         (when (string? x)
           (cache! name (string-append x "*"))))))
    (let* ((cur (notyet))
           (curlen (length cur)))
      (unless (null? cur)
        (for-each proc cur)
        (let* ((nex (notyet))
               (nexlen (length nex)))
          (when (= curlen nexlen)
            (error "We cannot resolve cterms for" nex))
          (resolve-pointer-base!)))))
  (define (cache-types!)
    (define types-stdc (append (types-entries (gen-types-stdc))
                               (types-entries (gen-types-stdint))))
    ;; Scan for types and cache type => c-type map
    ;; Import c standard type sets
    (for-each (lambda (e) (cache! (type-name e) (type-cterm e)))
              types-stdc)
    ;; FIXME: Allow different type sets here?
    ;; Import defined types
    (for-each (lambda (e) (cache! (type-name e) (type-cterm e)))
              types))

  (define (resolve-cterms sym)
    ;; Resolve type to c-terms (string)
    (or (hashtable-ref type-ht sym #f)
        (error "No matching cterms found" sym)))
  (cache-types!)
  (resolve-pointer-base!)
  resolve-cterms)


(define (basetype->ctype? sym)
  (case sym
    ((integer) 'signed)
    ((unsigned-integer) 'unsigned)
    ((real) 'real)
    ((blob) 'blob)
    ((pointer) 'pointer)
    ((array-pointer) 'pointer)
    ((enum-group) 'unsigned)
    ((flag-group) 'unsigned)
    ((void) 'void)
    (else #f)))

(define (basetype->ctype sym)
  (or (basetype->ctype? sym)
      (error "Invalid basetype" sym)))

(define (database->flatten/functions db)
  (define (maybe-null p m) (or (and m (not (null? m)) (p m)) '()))
  (define libinfo (database-libinfo db))
  (define types (types-entries (database-types db)))
  (define functions (maybe-null functions-entries (database-functions db)))
  (define resolve-type (make-resolve-type types))
  (define resolve-cterms (make-resolve-cterms types))

  ;;; Flatten DB template
  ;;;; Function
  (define (gen-func f)
    (define ret (function-return-argument f))
    (define arguments (function-arguments f))
    (define name (symbol->string (function-name f)))
    (define stub-types (function-stub-types f))
    (define (argone arg)
      (define argtype (argument-type arg))
      (define argtypesym (or argtype
                             (argument-c-type arg)))
      (define argnamesym (argument-name arg))
      (define argname (and argnamesym (symbol->string argnamesym)))
      `(,(resolve-type argtypesym)
         ,argname
         ,(resolve-cterms argtypesym)
         ,@(cond
             ((argument-input? arg) '(in))
             ((argument-output? arg) '(out))
             (else '()))))
    `(,name ,(if ret (list (argone ret)) '())
            ,(map argone arguments)
            ,@stub-types))

  (let ((myname (symbol->string (libinfo-c-name libinfo)))
        (func* (map gen-func functions)))
    (list myname func*)))


(define (database->flatten/constants db)
  (define (maybe-null p m) (or (and (not (null? m)) (p m)) '()))
  (define libinfo (database-libinfo db))
  (define types (types-entries (database-types db)))
  (define layouts (database-layouts db))
  (define aggregates (layouts-aggregates layouts))
  (define exports (maybe-null exports-entries (database-exports db)))
  (define resolve-type (make-resolve-type types))

  ;;; Flatten DB templates
  ;;;; aggregates
  (define (gen-aggregates)
    (define out '())
    (define (push! e) (set! out (cons e out)))
    (define (out-entry top-name cur-name ref-name a)
      (cond
        ((aggregate-entry-has-subaggregate? a)
         (let ((myname (symbol->string (aggregate-entry-name a)))
               (entries (aggregate-entry-subaggregate-entries a)))
           (let ((cur (string-append cur-name "/" myname))
                 (ref (string-append ref-name myname ".")))
             (for-each (lambda (e) (out-entry top-name cur ref e))
                       entries))))
        (else
          (let* ((type (resolve-type (aggregate-entry-type a)))
                 (myname (symbol->string (aggregate-entry-name a)))
                 (name (string-append
                         ref-name
                         myname))
                 (cur (string-append cur-name "/" myname)))
            (push! `(aggregate-entry ,cur ,type ,top-name ,name #f #f))))))
    (for-each (lambda (e)
                (let ((top-name (symbol->string (aggregate-name e))))
                 (for-each (lambda (a)
                             (out-entry top-name top-name "" a))
                           (aggregate-entries e))))
              aggregates)
    out)

  ;;;; layouts
  (define (gen-layouts)
    (define external-types
      (filter (lambda (t) (not (type-internal? t)))
              types))
    (define (gen-entry type)
      (define (gen-instance-type)
        (or (and (type-c-enum? type) 'c-enum)
            (and (type-c-struct? type) 'c-struct)
            (and (type-c-union? type) 'c-union)
            'value))
      (let ((name (symbol->string (type-name type)))
            (instance-type (gen-instance-type))
            (entrytype (resolve-type (type-name type))))
        `(layout ,name ,entrytype ,instance-type #f)))
    (map gen-entry external-types))

  ;;;; constants
  (define (gen-constants/exports)
    (define (gen e)
      (let ((name (symbol->string (export-name e)))
            (type (export-type e))
            (macro? (export-macro? e)))
        `(constant ,name ,(resolve-type type) #f #f
                   ,@(if macro? `((ifdef ,name)) '()))))
    (map gen exports))
  (define (gen-constants/enums)
    (define enum-groups 
      (filter (lambda (e) 
                (eq? 'enum-group 
                     (type-basetype e)))
              types))
    (apply 
      append 
      (map (lambda (e)
             (map (lambda (m)
                    ;; FIXME: Add ifdef ?
                    `(constant ,(symbol->string m)
                               unsigned
                               #f #f)) 
                  (type-members e))) 
           enum-groups)))


  (define (gen-constants)
    (append (gen-constants/exports)
            (gen-constants/enums)))

  ;; Construct return value
  (let ((myname (symbol->string (libinfo-c-name libinfo)))
        (constants (gen-constants))
        (layouts (gen-layouts))
        (aggregates (gen-aggregates)))
    (list myname (append constants
                         layouts
                         aggregates))))
         
)