# SwiftLogFireCloud


This library can be used as an implementation of SwiftLog that captures console logs from iOS and macOS apps and 
pushes them to Firebase Cloud Storage as flat files for later review.  It has the interent bias to retain a positive user experience
of the client app and therefore opts to lose logs over consuming badnwidth or excesseive retry failure processing.  Controlling 
whether the library will log to the cloud can be controlled at runtime by the client app and even remotely via a Firestore doc listener, an exercise 
left to the reader


This library violates the fundamental rule of software engineering:  never let the software engineering manager write code.  You've be warnred.
