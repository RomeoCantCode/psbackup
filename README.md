# psbackup
Decentralized backup from different sources to different destinations

Debug: For debugging uncomment the Write-Host commandlets

Script goals: Backup multiple (not so tiny) files from different sources to different destinations, so you can just add random (inexpensive) disks to the backup pool. Also make sure files get checked on a regular basis, so no bit errors occur. Decentralized structure, so every file can restored without having a huge database.
Advantages: Decentralized layout (.psbak XML files store all information). Add sources and destinations disks as you like. No Raids or JBOD necessary to add space.
Disadvantages: Inefficient when having a lot of tiny files (Uses lots of RAM >2M files / not multithreaded). Restore takes a lot of effort if source is lost (because all files are in a single folder and information has to be read from .psbak XML first). Does produce a lot of small files (.psbak for each file, literally doubles file count on FS).
Not recommended for: a lot of files (>1M), a lot of tiny files or folders with a lot of changes (eg >20 user working on files).
Please dont forget to do a proper backup to a different site (geo redundant), in case of fire/water/atomic war?/... 

Add property to file object "backupflag" which will be set to 0 whenever a file copy is started and set to 1 when file copy is over. When the file copy gets interrupted, it causes the files to get corrupt (you cant see any difference in file explorer).

Cleanup Summary: DST Orphan Files / PSBak, 

Add report to manually check about deleted files (retention is OK but you might not notice after a long period of time).

Add multithreading for better cpu usage https://adamtheautomator.com/powershell-multithreading/

MT goals: copy to different destinations / from different sources at same time. Calculate hashes at same time. get-childitem from differente src/dst at same time.

MT: add options for I/O Multithread (per disk, ?) and CPU Multithread 

Global excludefiles tbd

More efficiency: change += with .add / .remove / convert array to collections https://www.jonathanmedd.net/2014/01/adding-and-removing-items-from-a-powershell-array.html

Backup: Check if file fits to target disk before backup instead of just checking if disk limit is reached.

Recycle bin instead always reporting that a file will be deleted soon.
