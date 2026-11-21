{
  ephemeral.apps = {
    age = {
      label = "age";
      category = "Passwords";
      description = "encrypt files with a key or passphrase";
      package = "age";
    };
    keepassxc = {
      label = "KeePassXC";
      category = "Passwords";
      description = "offline password manager";
      package = "keepassxc";
    };
    bitwarden = {
      label = "Bitwarden";
      category = "Passwords";
      description = "password manager";
      package = "bitwarden-desktop";
    };
    wireshark = {
      label = "Wireshark";
      category = "Security testing";
      description = "network traffic analyser";
      warn = "you're added to the wireshark group; it can capture all traffic";
      nixos =
        { config, pkgs, ... }:
        {
          programs.wireshark = {
            enable = true;
            package = pkgs.wireshark;
          };
          users.users.${config.ephemeral.settings.username}.extraGroups = [ "wireshark" ];
        };
    };
    metasploit = {
      label = "Metasploit";
      category = "Security testing";
      description = "penetration testing framework with msfconsole";
      package = "metasploit";
    };
    nmap = {
      label = "Nmap";
      category = "Security testing";
      description = "network scanner and service detection";
      package = "nmap";
      warn = "with OpenSnitch on you're asked about each host a scan reaches";
    };
    zap = {
      label = "ZAP";
      category = "Security testing";
      description = "web app security scanner and proxy";
      package = "zap";
    };
    burpsuite = {
      label = "Burp Suite";
      category = "Security testing";
      description = "web security testing proxy (Community Edition)";
      package = "burpsuite";
      unfree = [ "burpsuite" ];
    };
    sqlmap = {
      label = "sqlmap";
      category = "Security testing";
      description = "SQL injection testing";
      package = "sqlmap";
    };
    ffuf = {
      label = "ffuf";
      category = "Security testing";
      description = "web fuzzer";
      package = "ffuf";
    };
    gobuster = {
      label = "Gobuster";
      category = "Security testing";
      description = "directory and DNS brute-forcing";
      package = "gobuster";
    };
    mitmproxy = {
      label = "mitmproxy";
      category = "Security testing";
      description = "interactive HTTPS proxy";
      package = "mitmproxy";
    };
    hashcat = {
      label = "Hashcat";
      category = "Security testing";
      description = "password recovery on the GPU";
      package = "hashcat";
    };
    john = {
      label = "John the Ripper";
      category = "Security testing";
      description = "password cracker";
      package = "john";
    };
    seclists = {
      label = "SecLists";
      category = "Security testing";
      description = "wordlists in /run/current-system/sw/share/wordlists/seclists";
      package = "seclists";
      nixos = {
        environment.pathsToLink = [ "/share/wordlists" ];
      };
    };
    exploitdb = {
      label = "Exploit-DB";
      category = "Security testing";
      description = "offline exploit archive searched with searchsploit";
      package = "exploitdb";
    };
    netexec = {
      label = "NetExec";
      category = "Security testing";
      description = "network service assessment (nxc)";
      package = "netexec";
    };
    ghidra = {
      label = "Ghidra";
      category = "Security testing";
      description = "reverse engineering suite";
      package = "ghidra";
    };
    radare2 = {
      label = "radare2";
      category = "Security testing";
      description = "command-line reverse engineering";
      package = "radare2";
    };
    binwalk = {
      label = "binwalk";
      category = "Security testing";
      description = "firmware analysis";
      package = "binwalk";
    };
    lynis = {
      label = "Lynis";
      category = "Security testing";
      description = "audits this system's hardening";
      package = "lynis";
    };
  };
}
