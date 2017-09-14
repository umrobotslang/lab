#load_z
#module load bazel
#bazel --output_base=./build/ build :deepmind_lab_gym_dummy
#bazel --output_base=./build/ run :random_agent --define headless=true -- --length=1 --level_script $1

export PATH="/z/home/shurjo/sw/bazel/bin:$PATH"
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
bazel run :random_agent --define headless=true -- --length=1 --level_script $1
