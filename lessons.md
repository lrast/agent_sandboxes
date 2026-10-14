# Lessons learned

## Networking

Checking for DNS routes for exfiltration: eg making lookups to DATACHUNK.malicious.com
Used tcpdump (as admin) to examine all traffic over the wire. Do requests in the vm trigger network calls?
- Host lookups (dig) do, internal lookups don't 
- internal lookups have cached tables, but can't find random prefixes, and never hit the wire
- restrict=on vs restrict=off changes this behavior. 


## Sandboxing

MacOS's `sandbox-exec` gives fine-grained privilege controls. It is depricated, but still seems heavily used.

