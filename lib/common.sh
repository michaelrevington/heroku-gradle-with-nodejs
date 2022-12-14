#!/usr/bin/env bash

gradle_build_file() {
  local buildDir=${1}
  if [ -f ${buildDir}/build.gradle.kts ]; then
    echo "${buildDir}/build.gradle.kts"
  else
    echo "${buildDir}/build.gradle"
  fi
}

has_stage_task() {
  local gradleFile="$(gradle_build_file ${1})"
   test -f ${gradleFile} &&
     test -n "$(grep "^ *task *stage" ${gradleFile})"
}

is_spring_boot() {
  local gradleFile="$(gradle_build_file ${1})"
   test -f ${gradleFile} &&
     (
       test -n "$(grep "^[^/].*org.springframework.boot:spring-boot" ${gradleFile})" ||
       test -n "$(grep "^[^/].*spring-boot-gradle-plugin" ${gradleFile})" ||
       test -n "$(grep "^[^/].*id.*org.springframework.boot" ${gradleFile})"
     ) &&
     test -z "$(grep "org.grails:grails-" ${gradleFile})"
}

is_ratpack() {
  local gradleFile="$(gradle_build_file ${1})"
  test -f ${gradleFile} &&
    test -n "$(grep "^[^/].*io.ratpack.ratpack" ${gradleFile})"
}

is_grails() {
  local gradleFile="$(gradle_build_file ${1})"
   test -f ${gradleFile} &&
     test -n "$(grep "^[^/].*org.grails:grails-" ${gradleFile})"
}

is_webapp_runner() {
  local gradleFile="$(gradle_build_file ${1})"
  test -f ${gradleFile} &&
    test -n "$(grep "^[^/].*io.ratpack.ratpack" ${gradleFile})"
}

create_build_log_file() {
  local buildLogFile=".heroku/gradle-build.log"
  echo "" > $buildLogFile
  echo "$buildLogFile"
}

# By default gradle will write its cache in `$BUILD_DIR/.gradle`. Rather than
# using the --project-cache-dir option, which muddies up the command, we
# symlink this directory to the cache.
create_project_cache_symlink() {
  local buildpackCacheDir="${1:?}/.gradle-project"
  local projectCacheLink="${2:?}/.gradle"
  if [ ! -d "$projectCacheLink" ]; then
    mkdir -p "$buildpackCacheDir"
    ln -s "$buildpackCacheDir" "$projectCacheLink"
    trap "rm -f $projectCacheLink" EXIT
  fi
}

# sed -l basically makes sed replace and buffer through stdin to stdout
# so you get updates while the command runs and dont wait for the end
# e.g. sbt stage | indent
output() {
  local logfile="$1"
  local c='s/^/       /'

  case $(uname) in
    Darwin) tee -a "$logfile" | sed -l "$c";; # mac/bsd sed: -l buffers on line boundaries
    *)      tee -a "$logfile" | sed -u "$c";; # unix/gnu sed: -u unbuffered (arbitrary) chunks of data
  esac
}

cache_copy() {
  rel_dir=$1
  from_dir=$2
  to_dir=$3
  rm -rf $to_dir/$rel_dir
  if [ -d $from_dir/$rel_dir ]; then
    mkdir -p $to_dir/$rel_dir
    cp -pr $from_dir/$rel_dir/. $to_dir/$rel_dir
  fi
}

install_jdk() {
  local install_dir=${1:?}
  local cache_dir=${2:?}

  let start=$(nowms)
  JVM_COMMON_BUILDPACK=${JVM_COMMON_BUILDPACK:-https://buildpack-registry.s3.us-east-1.amazonaws.com/buildpacks/heroku/jvm.tgz}
  mkdir -p /tmp/jvm-common
  curl --fail --retry 3 --retry-connrefused --connect-timeout 5 --silent --location $JVM_COMMON_BUILDPACK | tar xzm -C /tmp/jvm-common --strip-components=1
  source /tmp/jvm-common/bin/util
  source /tmp/jvm-common/bin/java
  source /tmp/jvm-common/opt/jdbc.sh
  mtime "jvm-common.install.time" "${start}"

  let start=$(nowms)
  install_java_with_overlay "${install_dir}" "${cache_dir}"
  mtime "jvm.install.time" "${start}"
} 

# install nodejs including npm
function install_node() {
	if [[ -v NODE_VERSION ]]; then
		NODE_VERSION="v${NODE_VERSION}"
		echo "NodeJS ${NODE_VERSION}"
	else
		NODE_VERSION="latest"
		echo "NodeJS latest is used."
	fi 
	
	NODE_SERVER="https://nodejs.org/dist/${NODE_VERSION}/"
	
	NODE_FILE="$(curl ${NODE_SERVER} | grep linux-x64.tar.gz | grep -oP node-.*.gz\")"
	if ! [[ -v NODE_FILE ]]; then 
		exit 1
	fi
		
	NODE_FILE=${NODE_FILE::-1}
	NODE_VERSION="$(echo ${NODE_FILE} | grep -oP v.*-l)"
	NODE_VERSION=${NODE_VERSION::-2}
	
	echo "NodeJS ${NODE_VERSION} found."
	
	echo "Downloading NodeJS..."
	eval curl "${NODE_SERVER}${NODE_FILE}" --output "${1}/${NODE_FILE}"
  echo "Download complete." 
 
  echo "Unzipping tarball..."
  eval gzip -d "/${1}/${NODE_FILE}"
  NODE_FILE=${NODE_FILE::-3}
  eval tar -xf "/${1}/${NODE_FILE}"
  NODE_FILE=${NODE_FILE::-4}
  echo "Unzip finished."  
   
  export PATH="${1}/${NODE_FILE}/bin:$PATH"   
  eval chmod +x ${1}/${NODE_FILE}/bin/npm
	
}