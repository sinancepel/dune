It is forbidden to declare two external implementations with the same variant.

  $ dune build --root 1/
  Entering directory '1'
  Error: Two implementations of vlibfoo have the same variant "somevariant":
  - impl2 (dune:11)
  - impl1 (dune:6)
  [1]

It is forbidden to declare an external implementation and have a local
implementation with the same variant.

  $ dune build --root 2 exe/exe.exe
  Entering directory '2'
  Error: Two implementations of vlibfoo have the same variant "somevariant":
  - impl2 (impl/dune:3)
  - impl1 (vlib/dune:6)
  [1]

  $ dune build --root 3 exe/exe.exe
  Entering directory '3'
  Error: Two implementations of vlibfoo have the same variant "somevariant":
  - impl1 (impl/dune:3)
  - impl1 (vlib/dune:6)
  [1]

