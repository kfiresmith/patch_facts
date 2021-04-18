#!/bin/bash
#
# Facts:
#  - OS-Release (string)
#  - Security errata support (boolean)
#  - EOL (boolean)
#  - All Outstanding Packages Count (integer)
#  - Security Outstanding Packages Count (integer)
#  - ISO-8601 Date of Collection (string)
#
# 2021-04-18 Kodiak Firesmith <firesmith@protonmail.com>

EOL=("centos5"
     "centos6"
     "rhel5"
     "rhel6"
     "debian6"
     "debian7"
     "debian8"
     "ubuntu12"
     "ubuntu14"
     "ubuntu16"
     )

# We use dead-simple tests to infer OS type
if [ -f /etc/apt/sources.list ]; then os_type=debian
elif [ -f /etc/yum.conf ]; then os_type=redhat
fi

function discern_debvers() {
  repostring="$(egrep "^deb " /etc/apt/sources.list | grep "updates main")"


  errata_support=true

  case "$repostring" in
    *squeeze*)
      distro=debian
      distrovers=6
      EOL=true
      ;;
    *wheezy*)
      distro=debian
      distrovers=7
      EOL=true
      ;;
    *jessie*)
      distro=debian
      distrovers=8
      EOL=true
      ;;
    *stretch*)
      distro=debian
      distrovers=9
      EOL=false
      ;;
    *buster*)
      distro=debian
      distrovers=10
      EOL=false
      ;;
    *lucid*)
      distro=ubuntu
      distrovers=10
      EOL=true
      ;;
    *precise*)
      distro=ubuntu
      distrovers=12
      EOL=true
      ;;
    *trusty*)
      distro=ubuntu
      distrovers=14
      EOL=true
      ;;
    *xenial*)
      distro=ubuntu
      distrovers=16
      EOL=true
      ;;
    *bionic*)
      distro=ubuntu
      distrovers=18
      EOL=false
      ;;
    *focal*)
      distro=ubuntu
      distrovers=20
      EOL=false
      ;;
    *groovy*)
      distro=ubuntu
      distrovers=20.10
      EOL=false
      ;;
    *hirsute*)
      distro=ubuntu
      distrovers=21.04
      EOL=false
      ;;
    *)
      exit 3
  esac
}

function debian_check_updates() {
  apt-get clean
  if [ -f "/usr/lib/update-notifier/apt-check" ]; then
    updatedata="$(/usr/lib/update-notifier/apt-check 2>&1)"
    security_updates="$(echo $updatedata | cut -d";" -f2)"
    all_updates="$(echo $updatedata | cut -d";" -f1)"
  else
    security_updates="$(apt-get upgrade -s | egrep '^Inst ' | grep -i security | wc -l)"
    all_updates="$(apt-get upgrade -s | egrep '^Inst ' | wc -l)"
  fi
}

case $os_type in
  debian)
    discern_debvers
    if $EOL; then
      security_updates=999
      all_updates=999
    else
      debian_check_updates
    fi
    ;;
  redhat)
    #stuff
    ;;
  *)
    exit 2
    ;;
esac

echo "EOL status is $EOL, security errata support is $errata_support, distro is $distro, distrovers is $distrovers, security update count is
$security_updates, all updates count is $all_updates"

