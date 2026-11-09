#!/bin/bash
# ==========================================================================
# healthcheck.sh
# Troubleshooting script for ticket ACME-6390 (Scripting for Server Security Part 2)
# Author: Mishelle
# Written with help from Claude (Anthropic AI) on Nov 8 2026, as allowed for
# requirement 3. I tested it on both servers: mishelle (Rocky Linux) and
# acmeserver (Ubuntu).
#
# WHAT IT DOES
#   Checks the areas I investigated during troubleshooting (network, network
#   config files, fstab, disk, services, logs, logrotate, recently changed
#   files, cron, users, open ports) and saves the results to a report file in
#   /var/log/healthcheck/. Any problem it finds is marked with "WARNING:".
#
# SETUP (nothing extra needs to be installed on Rocky or Ubuntu)
#   1. Download it:   wget <raw GitHub link to this file>         [WGET]
#   2. Install it:    sudo cp healthcheck.sh /usr/local/sbin/      [CP]
#   3. Make it run:   sudo chmod +x /usr/local/sbin/healthcheck.sh [CHMOD]
#   4. Run as root:   sudo /usr/local/sbin/healthcheck.sh
#   5. Read report:   sudo cat /var/log/healthcheck/<newest file>  [CAT]
#
# CITATIONS: each line has a tag in brackets that points to a source below.
#   [AI]         Claude (Anthropic) helped write this script, Nov 8 2026
#   [BASH]       GNU Bash manual: https://www.gnu.org/software/bash/manual/bash.html
#   [LAB]        Commands I used while troubleshooting this lab (ACME-6390)
#   [AWK]        GNU awk manual: https://www.gnu.org/software/gawk/manual/gawk.html
#   [BLKID]      https://man7.org/linux/man-pages/man8/blkid.8.html
#   [CAT]        https://man7.org/linux/man-pages/man1/cat.1.html
#   [CHMOD]      https://man7.org/linux/man-pages/man1/chmod.1.html
#   [CP]         https://man7.org/linux/man-pages/man1/cp.1.html
#   [CUT]        https://man7.org/linux/man-pages/man1/cut.1.html
#   [CRONTAB]    https://man7.org/linux/man-pages/man1/crontab.1.html
#   [DATE]       https://man7.org/linux/man-pages/man1/date.1.html
#   [DF]         https://man7.org/linux/man-pages/man1/df.1.html
#   [ECHO]       https://man7.org/linux/man-pages/man1/echo.1.html
#   [FIND]       https://man7.org/linux/man-pages/man1/find.1.html
#   [FINDMNT]    https://man7.org/linux/man-pages/man8/findmnt.8.html
#   [FSTAB]      https://man7.org/linux/man-pages/man5/fstab.5.html
#   [GETENT]     https://man7.org/linux/man-pages/man1/getent.1.html
#   [GREP]       https://man7.org/linux/man-pages/man1/grep.1.html
#   [HEAD]       https://man7.org/linux/man-pages/man1/head.1.html
#   [HOSTNAME]   https://man7.org/linux/man-pages/man1/hostname.1.html
#   [INTERFACES] https://manpages.ubuntu.com/manpages/noble/man5/interfaces.5.html
#   [IP]         https://man7.org/linux/man-pages/man8/ip.8.html
#   [IPROUTE]    https://man7.org/linux/man-pages/man8/ip-route.8.html
#   [JOURNALCTL] https://man7.org/linux/man-pages/man1/journalctl.1.html
#   [LOGROTATE]  https://man7.org/linux/man-pages/man8/logrotate.8.html
#   [LS]         https://man7.org/linux/man-pages/man1/ls.1.html
#   [LSBLK]      https://man7.org/linux/man-pages/man8/lsblk.8.html
#   [MKDIR]      https://man7.org/linux/man-pages/man1/mkdir.1.html
#   [NETPLAN]    https://netplan.readthedocs.io/en/stable/
#   [OSRELEASE]  https://man7.org/linux/man-pages/man5/os-release.5.html
#   [PASSWD]     https://man7.org/linux/man-pages/man5/passwd.5.html
#   [PING]       https://man7.org/linux/man-pages/man8/ping.8.html
#   [SORT]       https://man7.org/linux/man-pages/man1/sort.1.html
#   [SS]         https://man7.org/linux/man-pages/man8/ss.8.html
#   [SYSTEMCTL]  https://man7.org/linux/man-pages/man1/systemctl.1.html
#   [TAIL]       https://man7.org/linux/man-pages/man1/tail.1.html
#   [UPTIME]     https://man7.org/linux/man-pages/man1/uptime.1.html
#   [WC]         https://man7.org/linux/man-pages/man1/wc.1.html
#   [WGET]       https://www.gnu.org/software/wget/manual/wget.html
# ==========================================================================

# ---------- Settings ----------
REPORT_DIR="/var/log/healthcheck"                                   # folder where reports are saved [BASH][AI]
STAMP="$(date +%Y-%m-%d_%H%M)"                                      # date and time for the file name [DATE][AI]
REPORT="$REPORT_DIR/healthcheck_$(hostname)_$STAMP.txt"             # full report path, includes hostname [HOSTNAME][BASH]
WARNINGS=0                                                          # counts how many problems were found [BASH][AI]

# ---------- Must run as root ----------
if [ "$EUID" -ne 0 ]; then                                          # EUID 0 means root [BASH]
    echo "Please run as root: sudo $0"                              # tell the user how to run it [ECHO]
    exit 1                                                          # stop with an error code [BASH]
fi                                                                  # end of root check [BASH]

# ---------- Helper functions ----------
section() {                                                         # prints a heading for each check [BASH][AI]
    echo ""                                                         # blank line for readability [ECHO]
    echo "===== $1 ====="                                           # heading text [ECHO]
}                                                                   # end of section function [BASH]

warn() {                                                            # prints a warning and counts it [BASH][AI]
    echo "WARNING: $1"                                              # the warning message [ECHO]
    WARNINGS=$((WARNINGS + 1))                                      # add one to the warning count [BASH]
}                                                                   # end of warn function [BASH]

ok() {                                                              # prints a passed check [BASH][AI]
    echo "OK: $1"                                                   # the OK message [ECHO]
}                                                                   # end of ok function [BASH]

check_ips_in_file() {                                               # finds impossible IP addresses in a config file [BASH][AI]
    local file="$1"                                                 # the file to check [BASH]
    [ -r "$file" ] || return                                        # skip files that do not exist [BASH]
    local found_bad=0                                               # tracks if this file had a bad IP [BASH][AI]
    while read -r ip; do                                            # loop over each IP found in the file [BASH]
        local addr="${ip%%/*}"                                      # remove /24 style suffix [BASH]
        local bad=0                                                 # assume this IP is fine [BASH][AI]
        IFS='.' read -r -a parts <<< "$addr"                        # split the IP on the dots [BASH]
        [ "${#parts[@]}" -ne 4 ] && bad=1                           # an IPv4 address must have 4 numbers [BASH][AI]
        for p in "${parts[@]}"; do                                  # check each number [BASH]
            [ "$p" -gt 255 ] 2>/dev/null && bad=1                   # each number must be 0 to 255 [BASH][AI]
        done                                                        # end of number loop [BASH]
        if [ "$bad" -eq 1 ]; then                                   # if this IP is impossible [BASH]
            warn "invalid IP address '$ip' in $file"                # report it [AI]
            found_bad=1                                             # remember this file had a problem [BASH]
        fi                                                          # end of bad IP check [BASH]
    done < <(grep -v '^[[:space:]]*#' "$file" | grep -oE '[0-9]+(\.[0-9]+)+(/[0-9]+)?')  # skip comments, pull out IPs [GREP][BASH][AI]
    [ "$found_bad" -eq 0 ] && ok "no invalid IP addresses in $file" # say the file looks fine [BASH][AI]
}                                                                   # end of check_ips_in_file function [BASH]

# ---------- All the checks ----------
run_checks() {                                                      # every check lives in this function [BASH][AI]

    section "SYSTEM INFO"                                           # heading [AI]
    echo "Hostname: $(hostname)"                                    # which server this is [HOSTNAME]
    echo "Date:     $(date)"                                        # when the check ran [DATE]
    grep PRETTY_NAME /etc/os-release                                # which Linux version [GREP][OSRELEASE]
    uptime                                                          # how long the server has been up [UPTIME]

    section "NETWORK"                                               # heading [AI]
    ip -brief address                                               # network cards and their IP addresses [IP][LAB]
    if ip route | grep -q '^default'; then                          # is there a default route? [IPROUTE][GREP][LAB]
        ok "default route: $(ip route | grep '^default')"           # show the default route [IPROUTE][LAB]
    else                                                            # no default route found [BASH]
        warn "no default route, the server cannot reach the internet"  # this was the Ubuntu problem [LAB]
    fi                                                              # end of route check [BASH]
    if ping -c 2 -W 3 8.8.8.8 > /dev/null 2>&1; then                # can we reach an internet IP? [PING][LAB]
        ok "can reach 8.8.8.8"                                      # internet works [PING]
    else                                                            # ping failed [BASH]
        warn "cannot reach 8.8.8.8 (network unreachable)"           # internet does not work [PING][LAB]
    fi                                                              # end of ping check [BASH]
    if getent hosts google.com > /dev/null 2>&1; then               # can we turn a name into an IP (DNS)? [GETENT][AI]
        ok "DNS lookup of google.com works"                         # DNS works [GETENT]
    else                                                            # DNS failed [BASH]
        warn "DNS lookup of google.com failed"                      # matches 'Temporary failure in name resolution' [GETENT][LAB]
    fi                                                              # end of DNS check [BASH]

    section "NETWORK CONFIG FILES"                                  # heading [AI]
    for f in /etc/netplan/*.yaml; do                                # each netplan file (Ubuntu) [BASH][NETPLAN][LAB]
        [ -e "$f" ] || continue                                     # skip if there are none (Rocky) [BASH]
        ls -l "$f"                                                  # show the file and when it changed [LS][LAB]
        check_ips_in_file "$f"                                      # look for impossible IPs [AI]
    done                                                            # end of netplan loop [BASH]
    if [ -f /etc/network/interfaces ]; then                         # the older Debian/Ubuntu network file [BASH][INTERFACES][LAB]
        ls -l /etc/network/interfaces                               # show when it changed [LS][LAB]
        check_ips_in_file /etc/network/interfaces                   # look for impossible IPs [AI]
        for iface in $(awk '$1=="iface" {print $2}' /etc/network/interfaces); do  # each interface named in the file [AWK][INTERFACES]
            [ "$iface" = "lo" ] && continue                         # skip the loopback interface [BASH]
            ip link show "$iface" > /dev/null 2>&1 || warn "interface '$iface' in /etc/network/interfaces does not exist"  # name must match a real card [IP][AI]
        done                                                        # end of interface loop [BASH]
    fi                                                              # end of interfaces check [BASH]
    for f in /etc/sysconfig/network-scripts/ifcfg-* /etc/NetworkManager/system-connections/*; do  # Rocky network files [BASH][AI]
        [ -f "$f" ] || continue                                     # skip if none exist [BASH]
        check_ips_in_file "$f"                                      # look for impossible IPs [AI]
    done                                                            # end of Rocky network loop [BASH]

    section "FSTAB (drives mounted at boot)"                        # heading [AI]
    if findmnt --verify > /tmp/findmnt_check.txt 2>&1; then         # check fstab for errors [FINDMNT][LAB]
        ok "findmnt --verify found no problems"                     # fstab passed [FINDMNT]
    else                                                            # findmnt found problems [BASH]
        warn "findmnt --verify found problems:"                     # this was the Rocky problem [FINDMNT][LAB]
        cat /tmp/findmnt_check.txt                                  # show what it found [CAT]
    fi                                                              # end of findmnt check [BASH]
    while read -r dev mnt rest; do                                  # read each fstab line [BASH][FSTAB]
        case "$dev" in ""|\#*) continue ;; esac                     # skip blank lines and comments [BASH]
        if [[ "$dev" == UUID=* ]]; then                             # device listed by UUID [BASH][FSTAB]
            blkid -U "${dev#UUID=}" > /dev/null 2>&1 || warn "fstab device $dev was not found"  # does that UUID exist? [BLKID][AI]
        elif [[ "$dev" == /dev/* ]]; then                           # device listed by name like /dev/sda1 [BASH][FSTAB]
            [ -e "$dev" ] || warn "fstab device $dev does not exist"  # does that device exist? [BASH][LAB]
        fi                                                          # end of device check [BASH]
        if [[ "$mnt" == /* ]] && [ ! -d "$mnt" ]; then              # mount point must be an existing folder [BASH][FSTAB]
            warn "fstab mount point $mnt does not exist"            # folder is missing [LAB]
        fi                                                          # end of mount point check [BASH]
    done < /etc/fstab                                               # read from the fstab file [BASH][FSTAB]
    lsblk                                                           # list the real disks for comparison [LSBLK][LAB]

    section "DISK SPACE"                                            # heading [AI]
    df -h                                                           # how full each drive is [DF][LAB]
    while read -r mp use; do                                        # loop over drives 90% or more full [BASH][AI]
        warn "$mp is $use full"                                     # report full drives [AI]
    done < <(df -P | awk 'NR>1 && $5+0 >= 90 {print $6, $5}')       # find drives 90% or more full [DF][AWK][AI]

    section "FAILED SERVICES"                                       # heading [AI]
    FAILED=$(systemctl --failed --no-legend --plain | wc -l)        # count failed services [SYSTEMCTL][WC][LAB]
    if [ "$FAILED" -eq 0 ]; then                                    # none failed [BASH]
        ok "no failed services"                                     # services are fine [SYSTEMCTL]
    else                                                            # some failed [BASH]
        warn "$FAILED failed service(s):"                           # report the count [AI]
        systemctl --failed --no-legend --plain                      # list them [SYSTEMCTL][LAB]
    fi                                                              # end of service check [BASH]

    section "RECENT ERRORS IN LOGS (last 20 since boot)"            # heading [AI]
    journalctl -p err -b --no-pager | tail -n 20                    # error messages since last boot [JOURNALCTL][TAIL][LAB]

    section "LOGROTATE CONFIG"                                      # heading [AI]
    if command -v logrotate > /dev/null 2>&1; then                  # is logrotate installed? [BASH]
        ls -l /etc/logrotate.conf                                   # show size and when it changed [LS][LAB]
        if logrotate -d /etc/logrotate.conf 2>&1 | grep -qi '^error'; then  # test run, look for errors [LOGROTATE][GREP][LAB]
            warn "logrotate.conf has errors:"                       # this was an Ubuntu problem [LAB]
            logrotate -d /etc/logrotate.conf 2>&1 | grep -i '^error' | head -n 10  # show the errors [LOGROTATE][GREP][HEAD]
        else                                                        # no errors [BASH]
            ok "logrotate.conf test run had no errors"              # logrotate is fine [LOGROTATE]
        fi                                                          # end of logrotate check [BASH]
    fi                                                              # end of installed check [BASH]

    section "CONFIG FILES CHANGED IN THE LAST 24 HOURS (/etc)"      # heading [AI]
    find /etc -type f -mmin -1440 -printf '%TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort  # recently changed files, oldest first [FIND][SORT][LAB]
    echo "(Review this list. Changes you did not make are suspicious.)"  # reminder for the reader [ECHO][AI]

    section "SCHEDULED TASKS (cron)"                                # heading [AI]
    echo "Root crontab:"                                            # label [ECHO]
    crontab -l 2>/dev/null || echo "(none)"                         # root's cron jobs [CRONTAB][LAB]
    ls -l /etc/cron.d                                               # system cron jobs [LS][LAB]

    section "USERS"                                                 # heading [AI]
    EXTRA_ROOT=$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd)  # other accounts with root's ID [AWK][PASSWD][AI]
    if [ -n "$EXTRA_ROOT" ]; then                                   # found some [BASH]
        warn "accounts with root power (UID 0): $EXTRA_ROOT"        # report them [AI]
    else                                                            # none found [BASH]
        ok "only root has UID 0"                                    # users look fine [PASSWD]
    fi                                                              # end of UID check [BASH]
    echo "Accounts that can log in:"                                # label [ECHO]
    grep -vE '(nologin|false)$' /etc/passwd | cut -d: -f1           # users with a real login shell [GREP][CUT][PASSWD][AI]

    section "OPEN PORTS"                                            # heading [AI]
    ss -tuln                                                        # ports the server is listening on [SS][LAB]

    section "SUMMARY"                                               # heading [AI]
    echo "Warnings found: $WARNINGS"                                # total problems [ECHO]
    if [ "$WARNINGS" -eq 0 ]; then                                  # nothing found [BASH]
        echo "No problems detected."                                # all clear [ECHO]
    else                                                            # problems found [BASH]
        echo "Search this report for 'WARNING:' to see each problem."  # where to look [ECHO][AI]
    fi                                                              # end of summary [BASH]
}                                                                   # end of run_checks function [BASH]

# ---------- Run everything ----------
mkdir -p "$REPORT_DIR"                                              # make the report folder if missing [MKDIR]
run_checks > "$REPORT" 2>&1                                         # run all checks, save output to the report [BASH][AI]
find "$REPORT_DIR" -name 'healthcheck_*.txt' -mtime +30 -delete     # delete reports older than 30 days [FIND][AI]
echo "Report saved to: $REPORT"                                     # tell the user where the report is [ECHO]
grep -E '^(WARNING|Warnings found)' "$REPORT"                       # show warnings on screen too [GREP][AI]
