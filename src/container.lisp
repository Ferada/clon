;;; container.lisp --- Container management for Clon

;; Copyright (C) 2008 Didier Verna

;; Author:        Didier Verna <didier@lrde.epita.fr>
;; Maintainer:    Didier Verna <didier@lrde.epita.fr>
;; Created:       Wed Jul  2 10:02:47 2008
;; Last Revision: Wed Jul  2 10:02:47 2008

;; This file is part of Clon.

;; Clon is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; Clon is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


;;; Commentary:

;; Contents management by FCM version 0.1.


;;; Code:

(in-package :clon)
(in-readtable :clon)


;; #### NOTE: I don't like putting this function here (before the CONTAINER
;; class, outside the sealing protocol section), but this lets me specify
;; directly the :accessor in the class below.
(defgeneric sealedp (item)
  (:documentation "Returns t if ITEM is sealed.")
  ;; This function is supposed to work even on non-container items (options
  ;; and strings) because of the add-to function below, hence the following
  ;; non-specialized default method:
  (:method (item)
    "Return t (consider non-container ITEMs as sealed)."
    t))



;; ============================================================================
;; The Traversable Class
;; ============================================================================

(defabstract traversable ()
  ((traversedp :documentation "The object's traversal state."
	       :initform nil
	       :accessor traversedp))
  (:documentation "The TRAVERSABLE class.
This class is used for traversing graphs with loop avoidance."))

(defgeneric untraverse (object)
  (:documentation "Reset OBJECT's traversal state, and return OBJECT.")
  (:method (object)
    "Do nothing by default."
    object)
  (:method :after ((traversable traversable))
    "Mark TRAVERSABLE as untraversed."
    (setf (traversedp traversable) nil)))



;; ============================================================================
;; The Container Class
;; ============================================================================

(defclass container (traversable)
  ((items :documentation "The items in the container."
	  :type list
	  :initform nil
	  :accessor container-items)
   (sealedp :documentation "Whether the container is sealed."
	    :initform nil
	    :accessor sealedp))
  (:documentation "The CONTAINER class.
This class is a mixin used in synopsis and groups to represent the program's
command-line hierarchy."))


;; ------------------
;; Traversal protocol
;; ------------------

(defmethod untraverse ((container container))
  "Untraverse all CONTAINER items."
  (dolist (item (container-items container))
    (untraverse item))
  container)



;; ============================================================================
;; The Sealing Protocol
;; ============================================================================

;; Contrary to SEALEDP, this function is not supposed to work on non-container
;; items, because sealing is manual (so you're supposed to know what you're
;; doing).
(defgeneric seal (container)
  (:documentation "Seal CONTAINER.")
  (:method :before ((container container))
    "Ensure that CONTAINER is not already sealed, and perform name clash check."
    (when (sealedp container)
      (error "Sealing container ~A: already sealed." container))
    (loop :for items :on (container-items container)
	  :while (cdr items)
	  :do (loop :for item2 in (cdr items)
		    :do (check-name-clash (car items) item2))))
  (:method((container container))
    "Mark CONTAINER as sealed."
    (setf (sealedp container) t)))



;; ============================================================================
;; The Addition Protocol
;; ============================================================================

;; #### NOTE: using a generic function here is overkill because no other
;; method is implemented anywhere else.
(defgeneric add-to (container item)
  (:documentation "Add ITEM to CONTAINER.")
  ;; There is currently no need to further specialize this function, as
  ;; everything is done below.
  (:method :before ((container container) item)
    "Ensure that ITEM is sealed and CONTAINER is not."
    (when (sealedp container)
      (error "Adding item ~A to container ~A: container sealed." item container))
    (unless (sealedp item)
      (error "Adding item ~A to container ~A: item not sealed." item
	     container)))
  (:method ((container container) item)
    "Add ITEM to CONTAINER."
    (endpush item (container-items container))))



;; ============================================================================
;; The Name Clash Check Protocol
;; ============================================================================

;; #### NOTE: currently, name clashes are considered on short and long names
;; independently. That is, it is possible to have a short name identical to a
;; long one, although I don't see why you would want to do that, and I should
;; probably prohibit it altogether.

(defgeneric check-name-clash (item1 item2)
  (:documentation ~"Check for name clash between ITEM1's options "
		  ~"and ITEM2's options.")
  (:method (item1 item2)
    "Do nothing (no name clash for a non-group or non-option ITEMs."
    (values))
  (:method ((container container) item2)
    "Check for name clash between CONTAINER's options and ITEM2's ones."
    (dolist (item1 (container-items container))
      (check-name-clash item1 item2)))
  (:method (item1 (container container))
    "Check for name clash between ITEM1's options and CONTAINER's ones."
    (dolist (item2 (container-items container))
      (check-name-clash item1 item2)))
  (:method ((container1 container) (container2 container))
    "Check for name clash between CONTAINER1's options and CONTAINER2's ones."
    (dolist (item1 (container-items container1))
      (dolist (item2 (container-items container2))
	(check-name-clash item1 item2)))))



;; ============================================================================
;; The Option Mapping Protocol
;; ============================================================================

(defgeneric mapoptions (func there)
  (:documentation "Map FUNC over all options in THERE.")
  (:method (func elsewhere)
    "Do nothing by default."
    (values))
  (:method (func (container container))
    "Map FUNC over all options in CONTAINER."
    (unless (traversedp container)
      (dolist (item (container-items container))
	(mapoptions func item))))
  (:method :after (func (container container))
    (setf (traversedp container) t)))

(defmacro do-options ((opt container) &body body)
  "Execute BODY with OPT bound to every option in CONTAINER."
  `(mapoptions (lambda (,opt) ,@body)
    (untraverse ,container)))



;; ============================================================================
;; The Option Searching Protocol
;; ============================================================================

(defun search-option-by-name (container &rest keys &key short-name long-name)
  "Search for option with either SHORT-NAME or LONG-NAME in CONTAINER.
When such an option exists, return two values:
- the option itself,
- the name that matched."
  (declare (ignore short-name long-name))
  (do-options (option container)
    (let ((name (apply #'match-option option keys)))
      (when name
	(return-from search-option-by-name (values option name))))))

(defun search-option-by-abbreviation (container partial-name)
  "Search for option abbreviated with PARTIAL-NAME in CONTAINER.
When such an option exists, return two values:
- the option itself,
- the completed name."
  (let ((shortest-distance most-positive-fixnum)
	closest-option)
    (do-options (option container)
      (let ((distance (option-abbreviation-distance option partial-name)))
	(when (< distance shortest-distance)
	  (setq shortest-distance distance)
	  (setq closest-option option))))
    (when closest-option
      (values closest-option
	      (complete-string partial-name (long-name closest-option))))))

(defgeneric search-option
    (there &rest keys &key short-name long-name partial-name)
  (:documentation "Search for option in THERE.
The search is done with SHORT-NAME, LONG-NAME, or PARTIAL-NAME.
In case of a PARTIAL-NAME search, look for an option the long name of which
begins with it.
In case of multiple matches by PARTIAL-NAME, the longest match is selected.
When such an option exists, return wo values:
- the option itself,
- the name used to find the option, possibly completed if partial.")
  (:method
      ((container container) &rest keys &key short-name long-name partial-name)
    "Search for option in CONTAINER."
    (econd ((or short-name long-name)
	    (apply #'search-option-by-name container keys))
	   (partial-name
	    (search-option-by-abbreviation container partial-name)))))

(defgeneric search-sticky-option (there namearg)
  (:documentation "Search for a sticky option in THERE, matching NAMEARG.
NAMEARG is the concatenation of the option's short name and its argument.
In case of multiple matches, the option with the longest name is selected.
When such an option exists, return two values:
- the option itself,
- the argument part of NAMEARG.")
  (:method ((container container) namearg)
    "Search for a sticky option in CONTAINER matching NAMEARG."
    (let ((longest-distance 0)
	  closest-option)
      (do-options (option container)
	(let ((distance (option-sticky-distance option namearg)))
	  (when (> distance longest-distance)
	    (setq longest-distance distance)
	    (setq closest-option option))))
      (when closest-option
	(values closest-option (subseq namearg longest-distance))))))


;;; container.lisp ends here
