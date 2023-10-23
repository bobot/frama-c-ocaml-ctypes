# Generator of ocaml-ctypes binding using Frama-C #

This tool uses Frama-C to read header files of C libraries and generate the ocaml-ctypes description needed for generating the binding.

## Example ##

TBD but [example](./tests/simple.t)


## Why not generating directly the binding? ##

The tool could directly generate the C and OCaml code for the binding. However by using ocaml-ctypes we lift the work made to support new version of the runtime, and we benefit from the ocaml-ctypes ecosystem.