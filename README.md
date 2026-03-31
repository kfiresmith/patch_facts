# patch_facts
Generate OS patch facts for Ansible.

## Overview
`generate_patch_facts.sh` collects OS-reported patch and reboot status, formats it as JSON, and writes it to:

`/etc/ansible/facts.d/os_patch_status.fact`

The script is intended to run on a schedule, typically via cron or a systemd timer, so the data is already present when Ansible gathers facts. That avoids turning fact gathering into a live package-manager query, which can take several seconds and may fail noisily when repositories are unhealthy.

The script must be run as `root`.

## Supported platforms
The current script explicitly supports these distro families and versions:

- Debian 4 through 13
- Ubuntu 10.04 through 26.04
- CentOS 5 through 8
- RHEL 5 through 10
- Rocky Linux 8 through 10

## Output format
The script writes a single JSON object. When Ansible reads it as a local fact, the data appears under:

```json
"ansible_local": {
  "os_patch_status": {
    "...": "..."
  }
}
```

Important note: the script intentionally writes JSON string values for every field, including booleans and counts. In Ansible, values such as `"false"`, `"9"`, and `"unknown"` should therefore be treated as strings unless you explicitly cast them.

## Output fields
### `eol`
Whether the detected OS release is beyond its built-in support date.

Values:

- `"true"`
- `"false"`

This is derived from release-specific support end dates embedded in the script. Unknown releases are treated conservatively as effectively unsupported.

### `support_status`
The base support state determined from the detected distro and release, before considering any support extension such as Ubuntu ESM.

Values:

- `"supported"`
- `"eol"`
- `"unknown"`

### `support_extension`
Whether an additional vendor support extension is detected.

Values:

- `"none"`
- `"esm"`

At present, only Ubuntu Extended Security Maintenance is detected. Detection is based on `pro status --format json`, `ubuntu-advantage status --format json`, or ESM repository entries as a fallback.

### `effective_support_status`
The effective support state after applying any detected support extension.

Values:

- `"supported"`
- `"extended-support"`
- `"eol"`
- `"unknown"`

Typical interpretation:

- `"supported"` means the release is still within its normal support window.
- `"extended-support"` means the base release is EOL, but a supported extension was detected.
- `"eol"` means the release is out of support and no extension was detected.
- `"unknown"` means the release could not be mapped confidently.

### `errata_support`
Whether the platform exposes a usable distinction between security updates and non-security updates.

Values:

- `"true"`
- `"false"`

This is generally `"true"` on Debian, Ubuntu, RHEL, and Rocky Linux. It is `"false"` on CentOS, because CentOS does not provide reliable security errata metadata for its primary repositories.

### `security_updates`
The number of outstanding security updates.

Typical values:

- `"0"` or any non-negative integer encoded as a string
- `"-1"` when the platform does not provide trustworthy security update counts

Behavior by platform:

- Debian and Ubuntu: derived from `apt-check` when available, otherwise estimated from `apt-get -s upgrade`
- RHEL and Rocky Linux: derived from package-manager security queries
- CentOS: always `"-1"` because security errata reporting is not reliably available

### `all_updates`
The total number of outstanding package updates, including security and non-security updates.

Values:

- `"0"` or any non-negative integer encoded as a string

### `os_updates_broken`
Whether update detection encountered a package-manager or repository failure.

Values:

- `"true"`
- `"false"`

This is meant to catch cases such as broken repositories, failed metadata refresh, or unsupported package-manager execution paths that would make the reported counts unreliable.

### `needs_reboot`
Whether the OS appears to require a reboot to load patched kernel, library, or service state.

Values:

- `"true"`
- `"false"`
- `"unknown"`

Behavior by platform:

- Debian and Ubuntu: based on `/var/run/reboot-required`
- RHEL, Rocky Linux, and CentOS 7+: based on `needs-restarting -r` or package-manager equivalent when supported
- CentOS or RHEL 6: based on `needs-restarting` process output when available
- EL5-era systems or systems without supported reboot-check tooling: `"unknown"`

### `uptime_days`
Whole-number uptime in days, derived from `/proc/uptime`.

Values:

- `"0"` or any non-negative integer encoded as a string

Because the script uses integer arithmetic, uptimes below 24 hours are reported as `"0"`.

### `date_collected`
The collection timestamp in ISO-8601 format with timezone offset.

Example:

- `"2026-03-31T14:22-04:00"`

## Example fact payload
```json
{
  "ansible_local": {
    "os_patch_status": {
      "all_updates": "9",
      "date_collected": "2026-03-31T14:22-04:00",
      "effective_support_status": "supported",
      "eol": "false",
      "errata_support": "true",
      "needs_reboot": "false",
      "os_updates_broken": "false",
      "security_updates": "0",
      "support_extension": "none",
      "support_status": "supported",
      "uptime_days": "0"
    }
  }
}
```

## Operational notes
- Running the script updates package-manager metadata as part of its checks.
- Debian and Ubuntu paths run `apt-get clean` and `apt-get -qq update`.
- EL-family paths run the detected package manager with a cache clean before update counting.
- If you use this with Ansible, prefer scheduled execution before fact gathering rather than invoking the script directly as an executable fact.

## Recommendations and possible enhancements
The current script is in good shape for its primary job, but these documentation-backed improvements would likely add the most value:

- Add `os_updates_broken_reason` so repository and package-manager failures are easier to troubleshoot remotely.
- Add a `--debug` or verbose mode to show which detection path was used for support, updates, and reboot status.
- Add a self-test mode with fixtures so EOL, support-extension, and parser changes can be regression-tested without requiring live VMs.
- Consider documenting a sample cron entry or systemd timer unit in this repository so deployment is easier and more consistent.
- Consider documenting Ansible usage examples that cast string values into booleans or integers where needed.
- If future platform coverage matters, AlmaLinux support is the most obvious next addition because the EL-family logic is already close.

## Resources
- [Ansible Documentation for Local Facts](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html#adding-custom-facts)
