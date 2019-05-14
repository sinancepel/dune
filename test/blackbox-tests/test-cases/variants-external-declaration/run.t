Implementation of library from another project is allowed when explicitely
declared in the virtual library definition.

  $ dune build exe/exe.exe

  $ dune build -p vlibfoo

  $ cat _build/install/default/lib/vlibfoo/dune-package
  (lang dune 1.10)
  (name vlibfoo)
  (library
   (name vlibfoo)
   (kind normal)
   (virtual)
   (foreign_archives (native vlibfoo$ext_lib))
   (known_implementations (somevariant impl))
   (main_module_name Vlibfoo)
   (modes byte native)
   (modules
    (main_module_name Vlibfoo)
    (modules
     ((name Vlibfoo)
      (obj_name vlibfoo)
      (visibility public)
      (kind virtual)
      (intf)))
    (wrapped true)))
