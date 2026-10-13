Gemini
1. Persistent State Disk can be executed from ✅
2. Sandbox Exfiltration via Port 8181 - can outgoing connections be removed entirely? ✅
3. Write-Over of Orchestrator Files ✅
4. Global File Read Exposure ✅
5. Weak VM Credentials ✅


ChatGPT
1. not let persistent state be automatically executable ✅
2. Seatbelt profile: deny default on file read  ✅
3. mach-lookup and iokit-open are very broad host attack surfaces ✅
4. Your network rule creates an exfiltration capability ✅
5. You should probably eliminate the 8181 forwarding unless you really need it ✅
6. The QEMU snapshot itself is good ✅
7. I'd make the base image genuinely read-only at the host level if possible ✅
8. The state disk should ideally have a fixed UUID ✅
9. Your installation-time mkfs logic deserves tightening ✅
10. bot / bot password + SSH password authentication ✅
11. The installation network is appropriately less restricted ✅
12. separate "base creation" from "sandbox runtime" ✅

Claude
1. Critical: the guest account defeats your own privilege-separation goal 
    - pw ✅
    - admin ✅
2. Seatbelt profile: two scoped-too-broadly capabilities ✅
3. Seatbelt profile: an outbound rule that shouldn’t exist ✅
4. Seatbelt profile: (allow file-read*) is broader than it needs to be✅
5. Still no -monitor none -serial none ✅


## Further to-dos:
- Allowing connections to webservers
- Double check whether the bot account has admin

- test execute python scripts


