# Out of sync RPI rotation in some Android phone models running Exposure Notifications apps

## Authors: Alwen Tiu and Zak Brighton-Knight, The Australian National University


## 1. Summary of problems

[Google Exposure Notifications (EN) API](https://github.com/google/exposure-notifications-internals/blob/main/README.md) 
mentions that MAC may rotate without the RPI rotating, but whenever RPI rotates, MAC will be rotated at the same time 
(which is achieved by stopping and starting the EN BLE advertisement every time RPI rotates). 
Our experiments show that the latter is not universally true, that is, in some phone models, there is a small window
where RPI rotates without causing the MAC to rotate immediately, allowing one to observe (very briefly) two advertisement 
packets with the same MAC,  but with different RPIs. 
This may allow an attacker to track a phone running a contact tracing app that uses EN API, via MAC and RPI rotations. 

To facilitate the discussion below, we will use the following terminology to refer to out-of-sync (OoS) MAC/RPI rotations:
- Type 1 OoS: This refers to a situation where MAC changes but RPI does not. 
- Type 2 OoS: This is the converse of Type 1, i.e., RPI changes but MAC does not.


## 2. Steps to reproduce the attack

### Experiment setup

1. **Scanning device.** 
This is a standard laptop/desktop with a Bluetooth 4.2 adapter. In our experiments
we used a laptop and a desktop, each with an Intel bluetooth adapter supporting Bluetooth 4.2. Both were running Ubuntu 18.04.4 LTS, with bluez bluetooth protocol stack. This is a standard installation and no special configurations are required. In the following, we will refer to these devices as Computer 1 (desktop) and Computer 2 (laptop).

2. **Target phone.** For the target phones, we have tested several models. The next section lists all the models we tested on. Here we describe the result for one particular experiment, but the steps for other experiments are identical.
The following illustrates the result for the target phone Samsung Galaxy Note 5, running Android 7.0. 

3. **Target contact tracing app.** For this experiment, we chose SwissCovid. There was not particular reason; it was chosen as it was one of the earliest apps that use the EN API, and presumably has gone through more security and privacy assessments.

### Collecting scan data

First you need to enable bluetooth and start the SwissCovid app, and go through the necessary steps to activate the app. 

Next, run the scanner in the Ubuntu laptop/desktop. All the commands below were run under root.  

Open a terminal and escalate privilege to root and run: 
```bash
# hcitool lescan --duplicates
```
This will start the scanning process. 
Open another terminal as root and run:
```bash
# btmon --write hcitrace.snoop | tee hcitrace.txt
```
This command will capture the scanning information and write it to hcitrace.snoop file, and additionally, also capture the human-readable output in hcitrace.txt. We will mainly look at hcitrace.txt file to find the RPI rotation. The hcitrace.snoop file will have the complete information on the scanning process. 

To increase the coverage of the scan, it is advisable to run multiple scanning devices. In this experiment, we use two scanning devices (a laptop and a desktop). Since the RPI rotates every 15 minutes or so, we ran this experiment for a few hours to observe enough rotations. 

Let the scan run for a few hours so that you have enough data. To see the scan data relevant the EN advertisement (which is characterised by the service UUID 0xfd6f), we simply run: 
```bash
# grep -B 8 -A 2 "(0xfd6f)" hcitrace.txt > en.txt
```
This will produce a file en.txt containing only HCI events related to the EN scan responses. You may need to change the parameters '-B 8' (this will print the 8 lines before the matching line) and '-A 2' (this will print the two lines after the matching line) depending on the output format of your HCI scan. Here's an example of a scan result for my setup: 
  ````
  > HCI Event: LE Meta Event (0x3e) plen 40            #208704 [hci0] 3365.683786
      LE Advertising Report (0x02)
        Num reports: 1
        Event type: Non connectable undirected - ADV_NONCONN_IND (0x03)
        Address type: Random (0x01)
        Address: 59:5E:F9:C1:23:8F (Resolvable)
        Data length: 28
        16-bit Service UUIDs (complete): 1 entry
          Unknown (0xfd6f)
        Service Data (UUID 0xfd6f): 12ec68a558f69b3e332d303c222d6574f666f99a
        RSSI: -71 dBm (0xb9)
  ````

### Scan data analysis
This is simply done by extracting the frames that correspond to the scan data, and detect for changes in either MAC or RPI in those frames. We have written two shell scripts to do that: rot_frames.sh and rot_analyse.sh. 

If you just want to see the MAC/RPI rotations, run the rot_analyse.sh script. Here's the source code:
```shell
#!/bin/bash

grep -A 2 -B 8 "(0xfd6f)" hcitrace.txt > en.txt

pmac=""
prpi=""

while read -r line
do
  if [[ $line == *"Address:"* ]]; then
   # echo -n "MAC: ${line:9:17}, " 
     mac=${line:9:17}
  fi
  if [[ $line == *"Service Data"* ]]; then
    # echo "RPI: ${line:28}"
     rpi=${line:28}


     # Type 1 OoS: MAC rotates, but not RPI    
     if [[ $mac != $pmac && $rpi == $prpi ]]; then
        echo "[1] MAC: $mac, RPI: $rpi"
     fi

     # Type 2 OoS: RPI rotates but not MAC    
     if [[ $mac == $pmac && $rpi != $prpi ]]; then
        echo "[2] MAC: $mac, RPI: $rpi"
     fi

     # MAC and RPI rotate at the same time
     if [[ $mac != $pmac && $rpi != $prpi ]]; then
        echo "[-] MAC: $mac, RPI: $rpi"
     fi
     
     pmac=$mac
     prpi=$rpi 
  fi

done < en.txt

```
Here is an example of an analysis on an experiment on Samsung Galaxy Note 5, from the scan data collected using Computer 1:

````
[-] MAC: 6B:AE:2B:3B:37:53, RPI: 90a2db828ed67891d601c5158a242a77966fb011
[1] MAC: 6D:FE:91:58:F7:00, RPI: 90a2db828ed67891d601c5158a242a77966fb011
[2] MAC: 6D:FE:91:58:F7:00, RPI: 4a9416d4b000c07f739542f807a7920389d92696
[-] MAC: 49:A3:2A:12:22:D3, RPI: 338bc312462ad8cceac945f41bcfe45172bf7ada
[1] MAC: 48:0A:A3:B3:39:9E, RPI: 338bc312462ad8cceac945f41bcfe45172bf7ada
[2] MAC: 48:0A:A3:B3:39:9E, RPI: 159dcfb44a2d58e72f9a6abbf047242b92148697
[1] MAC: 78:A3:34:55:C6:B6, RPI: 159dcfb44a2d58e72f9a6abbf047242b92148697
[2] MAC: 78:A3:34:55:C6:B6, RPI: 39a0ea11b054ecd4112eb9585eda1aa06e1d88c6
[1] MAC: 59:5E:F9:C1:23:8F, RPI: 39a0ea11b054ecd4112eb9585eda1aa06e1d88c6
[2] MAC: 59:5E:F9:C1:23:8F, RPI: 12ec68a558f69b3e332d303c222d6574f666f99a
[-] MAC: 7E:DC:85:70:76:D9, RPI: 076bd4c4a841ec8ec9a0ac00ffde7240147e7cde
[1] MAC: 7D:BE:17:9A:43:42, RPI: 076bd4c4a841ec8ec9a0ac00ffde7240147e7cde
[2] MAC: 7D:BE:17:9A:43:42, RPI: 52a8d829c20b14a0c3bae42904ba909688695a5e
[1] MAC: 76:87:22:9F:7C:36, RPI: 52a8d829c20b14a0c3bae42904ba909688695a5e
[2] MAC: 76:87:22:9F:7C:36, RPI: e6919c2e4988f5d70eaace454e197c5683a78719
[1] MAC: 45:5E:08:C2:EC:E4, RPI: e6919c2e4988f5d70eaace454e197c5683a78719
[2] MAC: 45:5E:08:C2:EC:E4, RPI: edbfde24217a692e697196fc0247fd51c6ef834b
[1] MAC: 6E:6C:7F:EA:F1:CB, RPI: edbfde24217a692e697196fc0247fd51c6ef834b
[2] MAC: 6E:6C:7F:EA:F1:CB, RPI: e6554214e4be31db51355e417cf850f0af5bc436
[-] MAC: 4D:E3:73:18:0A:A3, RPI: 572bf20f070548c52ea6584c3cea9a1c00233c03
[1] MAC: 5D:00:1F:A7:9F:35, RPI: 572bf20f070548c52ea6584c3cea9a1c00233c03
[2] MAC: 5D:00:1F:A7:9F:35, RPI: ce376a0761f8ffb00640ed924d2b87c08975a9b6
[1] MAC: 42:D4:67:7C:20:CE, RPI: ce376a0761f8ffb00640ed924d2b87c08975a9b6
[2] MAC: 42:D4:67:7C:20:CE, RPI: b705e85b9f28571ff67a715c93cdad3115fafea8
[1] MAC: 73:5B:44:7A:27:95, RPI: b705e85b9f28571ff67a715c93cdad3115fafea8
[2] MAC: 73:5B:44:7A:27:95, RPI: 07a795fbe85c9decc2d082ccb0cb88af12a779b8
[1] MAC: 6B:AD:F2:FF:87:5F, RPI: 07a795fbe85c9decc2d082ccb0cb88af12a779b8
[2] MAC: 6B:AD:F2:FF:87:5F, RPI: 2867ab394086106de793b93158270eae6d43ca50
[1] MAC: 55:93:52:E8:0B:89, RPI: 2867ab394086106de793b93158270eae6d43ca50
[1] MAC: 69:4D:F2:DC:38:A1, RPI: 2867ab394086106de793b93158270eae6d43ca50
[2] MAC: 69:4D:F2:DC:38:A1, RPI: f62ef07ecf4ec77fabfb1a77bb17ad3498c7affa
[1] MAC: 65:EE:BB:FE:BB:54, RPI: f62ef07ecf4ec77fabfb1a77bb17ad3498c7affa
[-] MAC: 64:E7:6A:09:05:97, RPI: be43ca88bb09e029876300c40b7801c74caf6047
[1] MAC: 6D:BB:21:09:51:FF, RPI: be43ca88bb09e029876300c40b7801c74caf6047
[1] MAC: 6D:7C:58:86:35:EE, RPI: be43ca88bb09e029876300c40b7801c74caf6047
[2] MAC: 6D:7C:58:86:35:EE, RPI: 4d01dbb8081ee8654dbb3ea4c16ddda0507d4559
[1] MAC: 6E:37:19:5B:BD:31, RPI: 4d01dbb8081ee8654dbb3ea4c16ddda0507d4559
[-] MAC: 71:17:F6:45:A0:10, RPI: 2b83415479c68a9472583083489da0953a1588d4
[1] MAC: 68:53:E2:7C:E5:C4, RPI: 2b83415479c68a9472583083489da0953a1588d4
[1] MAC: 40:F1:C3:43:63:B5, RPI: 2b83415479c68a9472583083489da0953a1588d4
[2] MAC: 40:F1:C3:43:63:B5, RPI: bcead557dc3d96cd9b331e3a3075f72c6eeb9b25
[1] MAC: 44:78:78:83:9F:5D, RPI: bcead557dc3d96cd9b331e3a3075f72c6eeb9b25
[1] MAC: 6F:BE:F9:AE:6C:62, RPI: bcead557dc3d96cd9b331e3a3075f72c6eeb9b25
[2] MAC: 6F:BE:F9:AE:6C:62, RPI: a4ca4315ebb27618aad9001b57560fbb50e62b45
[1] MAC: 46:2D:00:A3:68:69, RPI: a4ca4315ebb27618aad9001b57560fbb50e62b45
[1] MAC: 44:BC:EA:15:E8:31, RPI: a4ca4315ebb27618aad9001b57560fbb50e62b45
[2] MAC: 44:BC:EA:15:E8:31, RPI: 204d857b02ee816e1f3b605e3091e5a1c0c7fec0
[1] MAC: 4A:12:3A:EB:B7:FD, RPI: 204d857b02ee816e1f3b605e3091e5a1c0c7fec0
[1] MAC: 63:C2:C8:1E:10:57, RPI: 204d857b02ee816e1f3b605e3091e5a1c0c7fec0
[2] MAC: 63:C2:C8:1E:10:57, RPI: 92cca0a300fe2e3b36575c17c4461075f06dccfa
[1] MAC: 6B:90:26:7B:EC:24, RPI: 92cca0a300fe2e3b36575c17c4461075f06dccfa
[2] MAC: 6B:90:26:7B:EC:24, RPI: 24fa81515560cfd7d674e0c991ff87996e300d8a
[1] MAC: 79:66:FD:CC:DC:70, RPI: 24fa81515560cfd7d674e0c991ff87996e300d8a
[2] MAC: 79:66:FD:CC:DC:70, RPI: f8cd9da3b0a7924b9fd63b6e8e75c422227838d3
````
The lines are ordered chronologically. 
Each line starts with one of the following prefixes:

- [1]: This denotes a Type 1 OoS, i.e., the MAC address in the current line is changed from the MAC in the previous line, but the RPI stays the same.

- [2]: This denotes a Type 2 OoS, i.e., the RPI in the current line is changed from the RPI in the previous line, but the MAC stays the same.

- [-]: This denotes that both the MAC and the RPI in the current line are changed from the MAC and RPI in the previous line, except when this is the first line (in which case, it just means that this is the first time the MAC/RPI are observed).

In the example above, we can see that there are segments of where both types of OoS are observed. Those segments represent interval of times when tracking is possible. The breaks in between segments do not necessarily represent perfect synchronisation of MAC/RPI rotations; it could mean that our scanning device may have missed an advertisement packet. Indeed, after performing the same analysis on the scan data collected in Computer 2 (in the same experiement), we obtained the following rotation:
````
[-] MAC: 4F:DD:AE:13:99:83, RPI: 081c1e15e7c44a57a7f6cb18004a8c1e81223222
[1] MAC: 6B:AE:2B:3B:37:53, RPI: 081c1e15e7c44a57a7f6cb18004a8c1e81223222
[2] MAC: 6B:AE:2B:3B:37:53, RPI: 90a2db828ed67891d601c5158a242a77966fb011
[1] MAC: 6D:FE:91:58:F7:00, RPI: 90a2db828ed67891d601c5158a242a77966fb011
[2] MAC: 6D:FE:91:58:F7:00, RPI: 4a9416d4b000c07f739542f807a7920389d92696
[1] MAC: 49:A3:2A:12:22:D3, RPI: 4a9416d4b000c07f739542f807a7920389d92696
[2] MAC: 49:A3:2A:12:22:D3, RPI: 338bc312462ad8cceac945f41bcfe45172bf7ada
[1] MAC: 48:0A:A3:B3:39:9E, RPI: 338bc312462ad8cceac945f41bcfe45172bf7ada
[2] MAC: 48:0A:A3:B3:39:9E, RPI: 159dcfb44a2d58e72f9a6abbf047242b92148697
[1] MAC: 78:A3:34:55:C6:B6, RPI: 159dcfb44a2d58e72f9a6abbf047242b92148697
[2] MAC: 78:A3:34:55:C6:B6, RPI: 39a0ea11b054ecd4112eb9585eda1aa06e1d88c6
[-] MAC: 59:5E:F9:C1:23:8F, RPI: 12ec68a558f69b3e332d303c222d6574f666f99a
[-] MAC: 7E:DC:85:70:76:D9, RPI: 076bd4c4a841ec8ec9a0ac00ffde7240147e7cde
[1] MAC: 7D:BE:17:9A:43:42, RPI: 076bd4c4a841ec8ec9a0ac00ffde7240147e7cde
[2] MAC: 7D:BE:17:9A:43:42, RPI: 52a8d829c20b14a0c3bae42904ba909688695a5e
[1] MAC: 76:87:22:9F:7C:36, RPI: 52a8d829c20b14a0c3bae42904ba909688695a5e
[2] MAC: 76:87:22:9F:7C:36, RPI: e6919c2e4988f5d70eaace454e197c5683a78719
[1] MAC: 45:5E:08:C2:EC:E4, RPI: e6919c2e4988f5d70eaace454e197c5683a78719
[2] MAC: 45:5E:08:C2:EC:E4, RPI: edbfde24217a692e697196fc0247fd51c6ef834b
[1] MAC: 6E:6C:7F:EA:F1:CB, RPI: edbfde24217a692e697196fc0247fd51c6ef834b
[2] MAC: 6E:6C:7F:EA:F1:CB, RPI: e6554214e4be31db51355e417cf850f0af5bc436
[1] MAC: 4D:E3:73:18:0A:A3, RPI: e6554214e4be31db51355e417cf850f0af5bc436
[2] MAC: 4D:E3:73:18:0A:A3, RPI: 572bf20f070548c52ea6584c3cea9a1c00233c03
[1] MAC: 5D:00:1F:A7:9F:35, RPI: 572bf20f070548c52ea6584c3cea9a1c00233c03
[2] MAC: 5D:00:1F:A7:9F:35, RPI: ce376a0761f8ffb00640ed924d2b87c08975a9b6
[1] MAC: 42:D4:67:7C:20:CE, RPI: ce376a0761f8ffb00640ed924d2b87c08975a9b6
[2] MAC: 42:D4:67:7C:20:CE, RPI: b705e85b9f28571ff67a715c93cdad3115fafea8
[1] MAC: 73:5B:44:7A:27:95, RPI: b705e85b9f28571ff67a715c93cdad3115fafea8
[2] MAC: 73:5B:44:7A:27:95, RPI: 07a795fbe85c9decc2d082ccb0cb88af12a779b8
[1] MAC: 6B:AD:F2:FF:87:5F, RPI: 07a795fbe85c9decc2d082ccb0cb88af12a779b8
[2] MAC: 6B:AD:F2:FF:87:5F, RPI: 2867ab394086106de793b93158270eae6d43ca50
[1] MAC: 55:93:52:E8:0B:89, RPI: 2867ab394086106de793b93158270eae6d43ca50
[1] MAC: 69:4D:F2:DC:38:A1, RPI: 2867ab394086106de793b93158270eae6d43ca50
[2] MAC: 69:4D:F2:DC:38:A1, RPI: f62ef07ecf4ec77fabfb1a77bb17ad3498c7affa
[1] MAC: 65:EE:BB:FE:BB:54, RPI: f62ef07ecf4ec77fabfb1a77bb17ad3498c7affa
[-] MAC: 64:E7:6A:09:05:97, RPI: be43ca88bb09e029876300c40b7801c74caf6047
[1] MAC: 6D:BB:21:09:51:FF, RPI: be43ca88bb09e029876300c40b7801c74caf6047
[1] MAC: 6D:7C:58:86:35:EE, RPI: be43ca88bb09e029876300c40b7801c74caf6047
[2] MAC: 6D:7C:58:86:35:EE, RPI: 4d01dbb8081ee8654dbb3ea4c16ddda0507d4559
[1] MAC: 6E:37:19:5B:BD:31, RPI: 4d01dbb8081ee8654dbb3ea4c16ddda0507d4559
[1] MAC: 71:17:F6:45:A0:10, RPI: 4d01dbb8081ee8654dbb3ea4c16ddda0507d4559
[2] MAC: 71:17:F6:45:A0:10, RPI: 2b83415479c68a9472583083489da0953a1588d4
[1] MAC: 68:53:E2:7C:E5:C4, RPI: 2b83415479c68a9472583083489da0953a1588d4
[1] MAC: 40:F1:C3:43:63:B5, RPI: 2b83415479c68a9472583083489da0953a1588d4
[2] MAC: 40:F1:C3:43:63:B5, RPI: bcead557dc3d96cd9b331e3a3075f72c6eeb9b25
[1] MAC: 44:78:78:83:9F:5D, RPI: bcead557dc3d96cd9b331e3a3075f72c6eeb9b25
[1] MAC: 6F:BE:F9:AE:6C:62, RPI: bcead557dc3d96cd9b331e3a3075f72c6eeb9b25
[2] MAC: 6F:BE:F9:AE:6C:62, RPI: a4ca4315ebb27618aad9001b57560fbb50e62b45
[1] MAC: 46:2D:00:A3:68:69, RPI: a4ca4315ebb27618aad9001b57560fbb50e62b45
[1] MAC: 44:BC:EA:15:E8:31, RPI: a4ca4315ebb27618aad9001b57560fbb50e62b45
[2] MAC: 44:BC:EA:15:E8:31, RPI: 204d857b02ee816e1f3b605e3091e5a1c0c7fec0
[1] MAC: 4A:12:3A:EB:B7:FD, RPI: 204d857b02ee816e1f3b605e3091e5a1c0c7fec0
[1] MAC: 63:C2:C8:1E:10:57, RPI: 204d857b02ee816e1f3b605e3091e5a1c0c7fec0
[2] MAC: 63:C2:C8:1E:10:57, RPI: 92cca0a300fe2e3b36575c17c4461075f06dccfa
[1] MAC: 6B:90:26:7B:EC:24, RPI: 92cca0a300fe2e3b36575c17c4461075f06dccfa
[2] MAC: 6B:90:26:7B:EC:24, RPI: 24fa81515560cfd7d674e0c991ff87996e300d8a
[1] MAC: 79:66:FD:CC:DC:70, RPI: 24fa81515560cfd7d674e0c991ff87996e300d8a
[2] MAC: 79:66:FD:CC:DC:70, RPI: f8cd9da3b0a7924b9fd63b6e8e75c422227838d3
````

We can see that the gap in Computer 1 analyss:
````
[2] MAC: 6D:FE:91:58:F7:00, RPI: 4a9416d4b000c07f739542f807a7920389d92696
[-] MAC: 49:A3:2A:12:22:D3, RPI: 338bc312462ad8cceac945f41bcfe45172bf7ada
````
was actually filled in the scan data from Computer 2:
````
[2] MAC: 6D:FE:91:58:F7:00, RPI: 4a9416d4b000c07f739542f807a7920389d92696
[1] MAC: 49:A3:2A:12:22:D3, RPI: 4a9416d4b000c07f739542f807a7920389d92696
[2] MAC: 49:A3:2A:12:22:D3, RPI: 338bc312462ad8cceac945f41bcfe45172bf7ada
````
Notice that the middle frame is observed in Computer 2, but was missed by Computer 1. 

The time duration for a segment can be calculated from the timestamp data in the HCI frames (which is available in the hcitrace.snoop file), but one can make a rough estimate easily as follows: let N be the number of Type 2 OoS in the fragment, then the duration of the fragment is roughly $(N-1)\times 15$ minutes, since RPI rotates every 15 minutes.

The above analysis only presents the MAC/RPI rotations. If you want to examine more closely the frames when the rotation happens, you can run the rot_frames.sh script:
```shell
#!/bin/bash
  
grep -A 2 -B 8 "(0xfd6f)" hcitrace.txt > en.txt
  
grep "Service Data" en.txt | uniq > rpi.txt

while read -r line
do
  echo "==============================================================================="
  echo "Rotation for RPI: ${line:28}"
  echo "==============================================================================="
  rpi=${line:28}
  grep -A 26 -B 9 $rpi en.txt | tail -n 48  
done < rpi.txt
```
This will produce groups of four frames, where the second and the third frames are the frames where the RPI is changed, and the other two are frames before and after this change. Here is an example of a group frames:
````
===============================================================================
Rotation for RPI: 338bc312462ad8cceac945f41bcfe45172bf7ada
===============================================================================
> HCI Event: LE Meta Event (0x3e) plen 40            #108749 [hci0] 1779.648822
    LE Advertising Report (0x02)
      Num reports: 1
      Event type: Non connectable undirected - ADV_NONCONN_IND (0x03)
      Address type: Random (0x01)
      Address: 49:A3:2A:12:22:D3 (Resolvable)
      Data length: 28
      16-bit Service UUIDs (complete): 1 entry
        Unknown (0xfd6f)
      Service Data (UUID 0xfd6f): 338bc312462ad8cceac945f41bcfe45172bf7ada
      RSSI: -86 dBm (0xaa)
--
> HCI Event: LE Meta Event (0x3e) plen 40            #108772 [hci0] 1780.001672
    LE Advertising Report (0x02)
      Num reports: 1
      Event type: Non connectable undirected - ADV_NONCONN_IND (0x03)
      Address type: Random (0x01)
      Address: 48:0A:A3:B3:39:9E (Resolvable)
      Data length: 28
      16-bit Service UUIDs (complete): 1 entry
        Unknown (0xfd6f)
      Service Data (UUID 0xfd6f): 338bc312462ad8cceac945f41bcfe45172bf7ada
      RSSI: -85 dBm (0xab)
--
> HCI Event: LE Meta Event (0x3e) plen 40            #108789 [hci0] 1780.257661
    LE Advertising Report (0x02)
      Num reports: 1
      Event type: Non connectable undirected - ADV_NONCONN_IND (0x03)
      Address type: Random (0x01)
      Address: 48:0A:A3:B3:39:9E (Resolvable)
      Data length: 28
      16-bit Service UUIDs (complete): 1 entry
        Unknown (0xfd6f)
      Service Data (UUID 0xfd6f): 159dcfb44a2d58e72f9a6abbf047242b92148697
      RSSI: -75 dBm (0xb5)
--
> HCI Event: LE Meta Event (0x3e) plen 40            #108796 [hci0] 1780.512684
    LE Advertising Report (0x02)
      Num reports: 1
      Event type: Non connectable undirected - ADV_NONCONN_IND (0x03)
      Address type: Random (0x01)
      Address: 48:0A:A3:B3:39:9E (Resolvable)
      Data length: 28
      16-bit Service UUIDs (complete): 1 entry
        Unknown (0xfd6f)
      Service Data (UUID 0xfd6f): 159dcfb44a2d58e72f9a6abbf047242b92148697
      RSSI: -75 dBm (0xb5)
--
````


## 3. List of phone models tested

We have performed tests on the following phone models (in no particular order). We have used the SwissCovid app in all tests, and we have not yet tested them using other EN API apps (my conjecture is they will all behave similarly, since the BLE
advertisement part is handled by the EN API, not the apps). 
For Samsung Galaxy S6 Edge, we observed 100% out of sync -- which means it is completely trackable. 
All of the tested phones are running their official firmwares; they have not been rooted and the bootloaders were locked. 
- Samsung Galaxy S8 (Android 9) - vulnerable 
- Samsung Galaxy S6 Edge (Android 7) - vulnerable
- Samsung Galaxy Note 5 (Android 7) - vulnerable
- Samsung Galaxy S7 (Android 8) - vulnerable
- Samsung Galaxy S7 Edge (Android 8) - vulnerable
- Samsung Galaxy A300 (Android 6 - Type 1 & 2 OoS not observed  
- Samsung J2 Pro (2018 - Android 7) - Type 2 OoS not observed  
- Samsung Galaxy S20 (Android 10) - Type 1 & 2 OoS not observed
- Google Nexus 5X (Android 6) - Type 1 & Type 2 OoS observed but very rarely.
- Google Pixel 4XL (Android 10) - Type 1 & 2 OoS not observed
- Huawei P30 (Android 10) -Type 2 OoS not observed
- Oppo Reno Z2 (Android 9) - Type 1/2 OoS not observed
- Google Pixel 2XL (Android 10) - Type 2 OoS not observed


Although for some models, out-of-sync RPI rotation was not observed,
we note that the experiments were performed using consumer grade bluetooth devices
(built-in bluetooth adapters of laptop/desktop). Using dedicated hardware scanners 
may allow a higher scanning resolution which may be able to observe a smaller
out of sync window that was not detected in my experiments. Our conjecture is 
if we scan the three BLE advertisement channels (channel 37, 38, 39) simultaneously
using dedicated hardware (e.g., Ubertooth) we may be able to observe more
frequent out-of-sync. 
We are currently performing more experiments using Ubertooth, scanning three advertisement channels
simultaneously. Early results indicate we are able to observe a shorter gap between
advertisements (some as low as 20ms, which is significantly smaller than the 200ms we observe
using our built-in laptop bluetooth adapters) and more OoS Type 2.

## 4. Attack scenario

The attacker in this case aims to track a phone running a contact tracing app that is based on EN API. The MAC/RPI out-of-sync rotation allows the attacker to link two MACs sharing the same RPI, or two RPIs sharing the same MAC. Note that the attacker will need both types of OoS to be able to track a phone continuously. 
Our current experiment shows that even with standard laptop/desktop, continous tracking up to a few hours is possible if the victim's phone is in within the bluetooth range. With dedicated scanning devices, this can potentially be further improved. Some of the gaps between segments of OoS can possibly be filled using other meta data, e.g., RSSI. 

The EN API specification anticipates the Type 1 OoS, and claims that Type 2 OoS does not happen; thus it claims that the tracking can be done only up to 15 minutes. This is possibly true for newer phone models as my experiments indicate, but certainly not true for older Samsung phone models. 


## 5. Potential mitigation

One potential mitigation could be to introduce some delay in between advertisements. Type 2 OoS is the interesting one, since Type 1 OoS doesn't seem possible to prevent. Preventing Type 2 OoS will limit the tracking to 15 minutes. From the scan data that I collected, it seems that Type 2 OoS happens only for a very short duration (less than 500ms typically). So introducing a couple of seconds delay, between the stopping of an old advertisement and the starting of a new advertisement, may prevent the attacker from observing the residual effect of the RPI rotations, and the delay should be negligible, as far as contact tracing is concerned. 


## 6. Related and Future Work

We first discovered this issue on August 6th 2020, and we intended to go through a responsible disclosure procedure, but we have just learned that on September 3rd 2020, [another group of researchers has identified the same issue](https://hackaday.com/2020/09/03/covid-tracing-framework-privacy-busted-by-bluetooth/) 
and has gone public with the details. Consequently we decided to release the full details of our on-going research. 

We are currently performing more thorough tests on a range of other phone models using dedicated bluetooth hardware scanners. 

## 7. Contact

If you would like to get in touch regarding this research, you can reach us through alwen.tiu@anu.edu.au. 

## 8. Acknowledgement

Thanks to Vanessa Teague and Jim Mussared for various insightful discussions regarding this research. 

