Compile-only declarations of the head unit's shared library `com.tcc.iap2`
(signatures only, written by us). At runtime the real classes come from the
system library through `<uses-library android:name="com.tcc.iap2"/>`.
These files are passed to javac/d8 as classpath and are never packaged.
