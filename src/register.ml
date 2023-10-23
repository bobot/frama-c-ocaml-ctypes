open Frama_c_kernel

module P = Plugin.Register (struct
  let name = "frama-c-ocaml-ctypes"
  let shortname = name
  let help = "Generate ocaml-ctypes definition from headers"
end)
