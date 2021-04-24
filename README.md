# patch_facts
Generate OS patch facts for Ansible

## General Function and Operation
The script `generate_patch_facts.sh` provides a single line of output to `/etc/ansible/facts.d/os_patch_status.fact`.

This script should be run via cron, so that the content is present on the system at time of fact gathering, rather
than be used as an executable fact, since querying the OS for patch status can take 2-10s.

### Output and fields

**eol:** This denotes whether the reported distro is EOL (end of life).  EOL denotes that updates are no longer available.

**errata_support:** This denotes whether the host distribution offers a mechanism to discern security patches from bugfixes.  Notably, CentOS does not provide this capability for it's main repos, only EPEL.

**security_updates:** This is the numeric count of outstanding security patches to be applied.

**all_updates:** This is the numeric count of all outstanding updates, both security and bugfix.

**os_updates_broken:** We attempt to catch cases where the OS patch reporting processes are not functional (eg, a broken repo gumming up the works), and report it so that it can be fixed.

**date_collected:** The ISO-8601 date/time of the last collection.  

```json
{
  "eol": "false",
  "errata_support": "true",
  "security_updates": "0",
  "all_updates": "0",
  "os_updates_broken": "false",
  "date_collected": "2021-04-24T08:58-04:00"
}
```

### Resources
[Ansible Documentation for Custom Facts](https://docs.ansible.com/ansible/latest/user_guide/playbooks_vars_facts.html#adding-custom-facts)
