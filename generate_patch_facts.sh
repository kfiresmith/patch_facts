#!/bin/bash
#
# Collect OS-reported software patch details, format them into JSON, and store
#   them as an Ansible fact.
#
# Limitations:
#   This script trusts your connection to upstream repositories and treats
#   their returned results as the holistic view of patching on the system.
#   This means if a repository is no longer present on the system, that it
#   won't catch any upstream patches from that repo.
#
# Room for future improvement:
#  - We should check for missing core repositories and treat that as updates being
#     broken
#  - We should figure out how to discern systems configured for extended support
#      and update their EOL status or otherwise denote they are under ESM/EUS/ELS
#
#  - We should probably add support for AlmaLinux
#
# Supports the following Linux variants and major versions:
#  - Debian 4 -> 13
#  - Ubuntu 10.04 -> 25.10
#
#  - CentOS 5 -> 8
#  - RHEL 5 -> 10
#  - Rocky Linux 8 -> 10
#
# Variables created:
#  - OS-Release (string)
#  - Security errata support (boolean)
#  - EOL (boolean)
#  - All Outstanding Packages Count (integer)
#  - Security Outstanding Packages Count (integer)
#  - ISO-8601 Date of Collection (string)
#
# 2022-05-03 Kodiak Firesmith <firesmith@protonmail.com>
#
#  - Updated 2023-04:
#     - Major rewrite of script to key EOL based on time rather than static settings
#     - Add true support for Rocky, and for RHEL/Rocky 9
#     - Use better OS identification scheme
#     - Full testing on Centos: 6,7 RHEL: 5,6,7,8 Rocky: 8,9
#         Debian & Ubuntu
#
#  - Updated 2022-05: Add support for Ubuntu 22.04 LTS, 21.10
#                     Set EOL on Debian 9, Ubuntu 21.04
#
#  - Updated 2021-06: Add extra capability for Rocky Linux.


# Don't let this script run w/o the ability to do things like update the package
#  cache.  And don't accidentally blow out /var/cache with non-root duplicates
#  of YUM caches.
running_as="$(whoami)" #Turns out we can't trust $USER to always be set :/
if [[ "$running_as" != "root" ]]; then
  echo "this script requires rootly powers"
  exit 2
fi

# Store output as Ansible fact?
store_ansible_fact=true

# Ansible fact name
factname=os_patch_status

# Ansible facts path; where we store our JSON output.
ansible_factspath=/etc/ansible/facts.d

# Simple ISO-8601 date
date_collected="$(date -I'minutes')"

# Determine uptime days in a pure-bash and multi-distro way, by performing integer
#  arithmetic based on uptime seconds as reported from /proc/uptime. Bash can't do floating
#  point math and we don't want to depend on something like `bc`.
# Because we have to use integers, and we don't want this to become complicated, uptimes from
#  0 seconds to 23 hours and 59 minutes will be '0 days up', and from thereon will be the whole
#  number of days up.
uptime_seconds="$(awk -F'.' '{print $1}' /proc/uptime)"
uptime_days="$(( $uptime_seconds / 60 / 60 / 24))"

epoch_now="$(date +%s)"

# By default, assume OS updates are not broken.  We check later on if they are.
os_updates_broken=false

# By default, set needs_reboot to unknown
needs_reboot=unknown

# EOL dates in epoch time, normalized to 23:59:59 UTC on the listed support end
# date from endoflife.date. For Debian this tracks Debian LTS; for Ubuntu it
# tracks Maintenance & Security Support; for RHEL it tracks Maintenance Support;
# for Rocky Linux it tracks Security Support.
eoldate_centos_5="1491004799"    # 2017-03-31
eoldate_centos_6="1606780799"    # 2020-11-30
eoldate_centos_7="1719791999"    # 2024-06-30
eoldate_centos_8="1640995199"    # 2021-12-31
eoldate_debian_etch="1266278399"     # 2010-02-15
eoldate_debian_lenny="1328572799"    # 2012-02-06
eoldate_debian_squeeze="1456790399"  # 2016-02-29
eoldate_debian_wheezy="1527811199"   # 2018-05-31
eoldate_debian_jessie="1593561599"   # 2020-06-30
eoldate_debian_stretch="1656719999"  # 2022-07-01
eoldate_debian_buster="1719791999"   # 2024-06-30
eoldate_debian_bullseye="1788220799" # 2026-08-31
eoldate_debian_bookworm="1846022399" # 2028-06-30
eoldate_debian_trixie="1909094399"   # 2030-06-30
#eoldate_redhatenterpriseserver_tikanga="1491004799"   # 2017-03-31
eoldate_rhel_5="1491004799"          # 2017-03-31
#eoldate_redhatenterpriseserver_santiago="1606780799"  # 2020-11-30
eoldate_rhel_6="1606780799"          # 2020-11-30
#eoldate_redhatenterpriseserver_maipo="1719791999"     # 2024-06-30
eoldate_rhel_7="1719791999"          # 2024-06-30
#eoldate_redhatenterprise_ootpa="1874966399"           # 2029-05-31
eoldate_rhel_8="1874966399"          # 2029-05-31
#eoldate_redhatenterprise_plow="1969660799"            # 2032-05-31
eoldate_rhel_9="1969660799"          # 2032-05-31
eoldate_rhel_10="2064268799"         # 2035-05-31
eoldate_rocky_8="1874966399"         # 2029-05-31
eoldate_rocky_9="1969660799"         # 2032-05-31
eoldate_rocky_10="2064268799"        # 2035-05-31
eoldate_ubuntu_lucid="1368143999"    # 2013-05-09 10.04 LTS
eoldate_ubuntu_precise="1493423999"  # 2017-04-28 12.04 LTS
eoldate_ubuntu_quantal="1400284799"  # 2014-05-16 12.10
eoldate_ubuntu_raring="1390867199"   # 2014-01-27 13.04
eoldate_ubuntu_saucy="1405641599"    # 2014-07-17 13.10
eoldate_ubuntu_trusty="1554249599"   # 2019-04-02 14.04 LTS
eoldate_ubuntu_utopic="1437695999"   # 2015-07-23 14.10
eoldate_ubuntu_vivid="1454630399"    # 2016-02-04 15.04
eoldate_ubuntu_wily="1469750399"     # 2016-07-28 15.10
eoldate_ubuntu_xenial="1617407999"   # 2021-04-02 16.04 LTS
eoldate_ubuntu_yakkety="1500595199"  # 2017-07-20 16.10
eoldate_ubuntu_zesty="1515887999"    # 2018-01-13 17.04
eoldate_ubuntu_artful="1532044799"   # 2018-07-19 17.10
eoldate_ubuntu_bionic="1685577599"   # 2023-05-31 18.04 LTS
eoldate_ubuntu_cosmic="1563494399"   # 2019-07-18 18.10
eoldate_ubuntu_disco="1579823999"    # 2020-01-23 19.04
eoldate_ubuntu_eoan="1594079999"     # 2020-07-06 19.10
eoldate_ubuntu_focal="1748735999"    # 2025-05-31 20.04 LTS
eoldate_ubuntu_groovy="1626998399"   # 2021-07-22 20.10
eoldate_ubuntu_hirsuite="1642723199" # 2022-01-20 21.04
eoldate_ubuntu_impish="1657843199"   # 2022-07-14 21.10
eoldate_ubuntu_jammy="1806623999"    # 2027-04-01 22.04 LTS
eoldate_ubuntu_kinetic="1689897599"  # 2023-07-20 22.10
eoldate_ubuntu_lunar="1705795199"    # 2024-01-20 23.04
eoldate_ubuntu_mantic="1720828799"   # 2024-07-12 23.10
eoldate_ubuntu_noble="1874966399"    # 2029-05-31 24.04 LTS
eoldate_ubuntu_oracular="1752191999" # 2025-07-10 24.10
eoldate_ubuntu_plucky="1768694399"   # 2026-01-17 25.04
eoldate_ubuntu_questing="1782950399" # 2026-07-01 25.10

# Collect details on the OS: Distribution [eg: ubuntu], Release [eg: 20.04], Codename [eg: focal]
function collect_os_details() {
  if command -v lsb_release >/dev/null 2>&1; then
      osdistribution="$(lsb_release -s -i | tr '[:upper:]' '[:lower:]')"
      osrelease="$(lsb_release -s -r | tr '[:upper:]' '[:lower:]')"
      oscodename="$(lsb_release -s -c | tr '[:upper:]' '[:lower:]')"
      # We need to normalize the distribution naming for RHEL, to cope with non-uniform values
      #  and also to match the output of the alternate os-release output when lsb_release is
      #  not present, as with RHEL 8 & 9
      if [[ x"${osdistribution:0:6}" == xredhat ]]; then
        osdistribution="rhel"
      fi
  else
    # For systems that don't have lsb_release, as a last ditch effort, we'll parse /etc/os-release
    if [[ -r /etc/os-release ]]; then
      os_id="$(grep -E ^ID= /etc/os-release | cut -f2 -d= | sed 's/"//g' | tr '[:upper:]' '[:lower:]')"
      if [[ x"$os_id" == xrocky || x"$os_id" == xrhel ]]; then
        osdistribution="$os_id"
        osrelease="$(grep -E '^VERSION_ID=' /etc/os-release | cut -f2 -d= | tr -d '"' | tr '[:upper:]' '[:lower:]')"
      else
        # If a system doesn't have lsb_release and isn't RHEL or Rocky, we want the job to fail
        #  and let us know about it so that we can write in support.
        echo "system unable to be identified"
        exit 2
      fi
    fi
  fi
}

function support_status() {
  # We have to do this because of a couple problems with Red Hat variants:
  #  1. Centos calls every codename "(Final)" - not helpful
  #  2. Rocky and RHEL fail to have lsb_release as part of their core command set
  if [[ x"$osdistribution" == xcentos || x"$osdistribution" == xrocky || x"$osdistribution" == xrhel ]]; then
    majrelease="$(echo $osrelease | cut -f1 -d.)"
    eoldate_string="eoldate_${osdistribution}_${majrelease}"
    if [[ x"${!eoldate_string}" < x$epoch_now ]]; then
      is_eol=true
    else
      is_eol=false
    fi
  else
    # Evaluate the eoldate - only a subset of possible OS distros and release codenames are
    #  covered in our static EOL date strings, so if those variables don't exist, we just
    #  compare 'x' against the much larger x + current epoch time.  Most EOL distros don't have
    #  a static EOL date string in this script
    eoldate_string="eoldate_${osdistribution}_${oscodename}"
    if [[ x"${!eoldate_string}" < x$epoch_now ]]; then
      is_eol=true
    else
      is_eol=false
    fi
  fi
}

# This is where we poll status on outstanding updates.
# We clean the APT cache, then force it to refresh.  By forcing APT cache 
#  refresh, we ensure we have the most current status for updates, and we catch
#  any hosts that have broken APT - a common cause for silent patch logjams.
function debian_check_updates() {
  errata_support=true
  apt-get clean
  apt-get -qq update 2>/dev/null || os_updates_broken=true
  if [ -f "/usr/lib/update-notifier/apt-check" ]; then
    updatedata="$(/usr/lib/update-notifier/apt-check 2>&1)"
    security_updates="$(echo $updatedata | cut -d";" -f2)"
    all_updates="$(echo $updatedata | cut -d";" -f1)"
  else
    security_updates="$(apt-get upgrade -s | egrep '^Inst ' | grep -i security | wc -l)"
    all_updates="$(apt-get upgrade -s | egrep '^Inst ' | wc -l)"
  fi
}

function redhat_check_updates() {
  errata_support=true
  yum -q clean all 1>/dev/null
  security_updates="$(yum -q --security check-update | wc -l)"
  all_updates="$(yum check-update -q | wc -l)"
}

# CentOS doesn't publish security errata, so we can't use `list security`.
# Instead we just toss out `-1` to make it easy to discern that this is a bogus value.
function centos_check_updates() {
  errata_support=false
  security_updates="-1"
  all_updates="$(yum check-update -q | wc -l)"
}

function ensure_ansible_factspath() {
  if [[ ! -d $ansible_factspath ]]; then
    mkdir -p $ansible_factspath
  fi
}

# Here's where we try to determine if a system needs to be rebooted in order
#   to load patched versions of the kernel, services, or libraries.

function needs_reboot() {
  case $osdistribution in
    # For Debian variants, this is easy and uniform across all common versions
    #   of Debian and Ubuntu.
    "debian" | "ubuntu")
      if [ -f /var/run/reboot-required ]; then
        needs_reboot=true
      else
        needs_reboot=false
      fi
    ;;
    "centos" | "rhel" | "rocky")
      case "$majrelease" in
        # For redhat variants this old, we can't easily determine if a system
        #   needs to be rebooted to apply packages, and in 2021 we should just
        #   throw the whole computer away if it's still running el5.
        "5")
          needs_reboot=unknown
          ;;
        # The needs-restarting binary is part of yum-utils, which is an optional
        #   package that we can't trust is installed.
        # Further, for el6, we don't get a determinative RC from running this 
        #   command, so we have to check for output, which only happens when
        #   a system has procs that need to be reloaded.
        "6")
          if [ -f "/usr/bin/needs-restarting" ]; then
            restartable_procs=$(/usr/bin/needs-restarting | wc -l)
            if (( $restartable_procs > 0 )); then
              needs_reboot=true
            else
              needs_reboot=false
            fi
          fi
          ;;
        # This is the catch-all with the understanding that if it's not el5 nor el6
        #   that it'll be el7+, which is a new enough version of yum-utils to use a
        #   determinative RC - 0: all good, 1: needs restarting.
        *)
          if [ -f "/usr/bin/needs-restarting" ]; then
            if /usr/bin/needs-restarting -r 1>/dev/null; then
              needs_reboot=false
            else
              needs_reboot=true
            fi
          else
            needs_reboot=unknown
          fi

          ;;
      esac
    ;;
  esac
}

# First we identify the OS and log some values
collect_os_details

# Then we check the EOL status of the system
support_status

# Next we check for the patching status
if [[ x"$osdistribution" == xdebian || x"$osdistribution" == xubuntu ]]; then
  debian_check_updates
elif [[ x"$osdistribution" == xrhel || x"$osdistribution" == xrocky ]]; then
  # If a system is RHEL or Rocky, we can check for security errata
  redhat_check_updates
elif [[ x"$osdistribution" == xcentos ]]; then
  # We need a separate check for CentOS because this OS doesn't provide security errata
  centos_check_updates
fi
  
# Finally we check to see if the system needs to be rebooted
needs_reboot

# Write those facts out!
if $store_ansible_fact; then
  ensure_ansible_factspath
  JSON_FMT='{"eol":"%s","errata_support":"%s","security_updates":"%s", "all_updates": "%s", "os_updates_broken": "%s", "needs_reboot": "%s", "uptime_days": "%s", "date_collected": "%s"}\n'
  printf "$JSON_FMT" "$is_eol" "$errata_support" "$security_updates" "$all_updates" "$os_updates_broken" "$needs_reboot" "$uptime_days" "$date_collected" > $ansible_factspath/$factname.fact
fi
