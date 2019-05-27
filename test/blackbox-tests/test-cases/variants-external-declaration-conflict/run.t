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

  $ dune build --root not-a-vlib
  Entering directory 'not-a-vlib'
  File "dune", line 5, characters 0-94:
  5 | (external_variant
  6 |   (virtual_library libfoo)
  7 |   (variant somevariant)
  8 |   (implementation impl1))
  Error: Library libfoo isn't a virtual library.
  [1]

  $ dune build --root not-a-vlib-redirect
  Entering directory 'not-a-vlib-redirect'
  File "dune", line 6, characters 0-94:
  6 | (external_variant
  7 |   (virtual_library libfoo)
  8 |   (variant somevariant)
  9 |   (implementation impl1))
  Error: To declare variants you must use libfoo's public name,
  which is another-name.
  [1]

  $ dune build --root vlib-dont-exist
  Entering directory 'vlib-dont-exist'
  File "dune", line 1, characters 0-100:
  1 | (external_variant
  2 |   (virtual_library i-dont-exist)
  3 |   (variant somevariant)
  4 |   (implementation impl1))
  Error: Virtual library i-dont-exist hasn't been found in the project.
  [1]
