Implementation of library from another project is not allowed when tagged with
variant.

  $ dune build
  File "prj2/dune", line 4, characters 13-20:
  4 |  (implements vlibfoo)
                   ^^^^^^^
  Error: Library implementation vlibfoo for variant "somevariant" implements a library 
  outside the project. Instead of using (variant "somevariant") here,
  you need to reference it in the virtual library definition, using 
  (external_implementations ("somevariant" impl)).
  [1]
