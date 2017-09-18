#%Module1.0
proc ModulesHelp { } {
global dotversion
puts stderr "deepmind-lab 0.0.1"
}

set app deepmind-lab
set version 0.0.1
set installDir [file dirname [exec readlink -m $ModulesCurrentModulefile]]

module-whatis "deepmind-lab 0.0.1"

conflict $app

# deepmind_lab as python library
prepend-path PYTHONPATH $installDir/../build/execroot/deepmind-lab/bazel-out/local-fastbuild/bin/deepmind_lab_gym_dummy.runfiles/org_deepmind_lab/python/
prepend-path PYTHONPATH $installDir/../build/execroot/deepmind-lab/bazel-out/local-fastbuild/bin/deepmind_lab_gym_dummy.runfiles/org_deepmind_lab/
