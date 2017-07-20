export PATH="/z/home/shurjo/sw/bazel/bin:$PATH"

JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 

bazel run :random_agent --define headless=false -- --length=1 --level_script $1
