#< General Information
#Autor: Romeo Loeffel
#Version: Alpha5 Testing WIP
#TBD: Error handling, cleanup/fileretention, log/eventlog
<#Notes
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

#>
#General Information
Try{
    #< Configuration - should be changed
    $global:Configedited = $true
    if($global:Configedited -eq $false){
       Throw "Configuration file not edited, please edit before first run!" 
    }
    $global:FileRetentionDays = 180 #will keep deleted files in destination until retention is expired
    $global:Algorithm = "SHA256" #algorithm used to generate hash
    $global:FreeSpaceLimitGB = 150 #free space in GB until next backup destination is used (checked after each file)
    $Sources = @("G:\Mycloud","E:\4TB Seagate","E:\4TB USB HDD","F:\2TB USB HDD","F:\5TB USB HDD","F:\Dario\Roms") #source array consisting of strings to all source folders (without ending \)
    $Destinations = @("U:\PS-Backup","V:\PS-Backup","W:\PS-Backup","Y:\PS-Backup","X:\PS-Backup") #destination arrray consisting of string to all destination folders (without ending \)
    #$Destinations = @("W:\PS-Backup")
    $global:HashExpireDays = 60
    $global:LogDir= "\log" #where should the log be saved whithing ProgramData Folder specified below.
    $global:ProcessPriority = "Idle" #Idle, Normal, BelowNormal, AboveNormal, Realtime, High. Default: Idle so the system wont be slowed down when calculating hashes.
    $global:MaxRunTime = 4 #TBD maximum run time in hours. after that time it will complete the current step and then exit.
    $global:AllowFileDeletion = $false #$true or $false
    $global:MaxThreads = 4 #TBD
    $global:ExcludeFiles = @() #TBD array of strings which exlude files. Example: @("*.txt","*.nfo","Thumbs.db")
    #> Configuration

    #< Variables - should not be changed
    $global:NewFiles = @() #files that are backed up the first time are listed here for summary
    $global:NewFiles = {$global:NewFiles}.invoke() #convert array to collection so you can freely add new entries in array with .add or remove with .remove
    $global:NewHashFiles = @() #files those hashes were calculated (first and hash timeout) are listed here for summary
    $global:NewHashFiles = {$global:NewHashFiles}.invoke()
    $global:DeletedSourceFiles = @() #files which were deleted in source are listed here for summary. those files will be deleted when retention time is over
    $global:DeletedSourceFiles = {$global:DeletedSourceFiles}.invoke()
    $global:DeletedBackupFiles = @() #files which were deleted in source and were now deleted in destination because retention time is over.
    $global:DeletedBackupFiles = {$global:DeletedBackupFiles}.invoke()
    #$global:TotalFilesSource = 0 #TBD total files in source, does not include .psbak files
    #$global:TotalFilesDestination = 0 #TBD total files in destination, does not include .psbak files
    #$global:TotalFilesSourceMB = 0 #TBD same as above but in MB
    #$global:TotalFilesDestinationMB = 0 # TBD same as above but in MB
    $global:FilesWithWarnings = @() #files which were given a warning (various reasons, usually then when console would write warning)
    $global:FilesWithWarnings = {$global:FilesWithWarnings}.invoke()

    $cApplicationName = "psbackup-alpha5"
    $global:ScriptStartDate = get-date
    $global:ProgramDataFolder = $env:ProgramData  + "\" + $cApplicationName
    #> Variables

    #< Installation / Checks
    if(Test-Path $global:ProgramDataFolder){
        Write-Host $global:ProgramDataFolder exists
    }
    else{
        New-Item -ItemType Folder -Path $global:ProgramDataFolder
        Write-Host "Folder created at" $global:ProgramDataFolder
    }
    Start-Transcript -Append -Path ($global:ProgramDataFolder+$global:LogDir+"\psbackup.log") 
    $currentprocess = Get-Process -Id $pid
    $currentprocess.PriorityClass = $global:ProcessPriority
    #>

    #< Class Definition
    Class File{ #a File object contains information on a certain file. The object's "primary key" (there is none because it isn't a database) would be $sourcepath and $destinationpath. The information for a file object should be obtained from a file or .psback file. 
        [string]$sourcepath #path to source of the file
        [string]$destinationpath #path to file in backup destination
        [bool]$backedup #was the file backed up?
        [bool]$hashed #already hashed?
        [system.object]$hash #hash of the file which was calculated
        [datetime]$hashdatetime #datetime when hash was generated
        [datetime]$deleteddatetime #datetime when the first time was when file was deleted in source
        File([string]$sourcepath,[string]$destinationpath,[bool]$backedup,[bool]$hashed,[system.object]$hash,[datetime]$hashdatetime,[datetime]$deleteddatetime){ #overload with all vars
            $this.sourcepath = $sourcepath
            $this.destinationpath = $destinationpath
            $this.backedup = $backedup
            $this.hashed = $hashed
            $this.hash = $hashed
            $this.hashdatetime = $hashdatetime
            $this.deleteddatetime = $deleteddatetime
        }
        cleanup(){ #cleanup should be used after backup to check for orphans(files, psbak), deleted files, ...? it should be used with destination folders listed in $Destinations array
            #load information from .psbak
            $this.loadpsbak()
            #$fileproperties = Get-ItemProperty -LiteralPath $this.destinationpath
            $date = get-date

            #check if file has psbak
            <#if(Test-Path -LiteralPath ($this.sourcepath + ".psbak")){
                #source psbak exists for this file
            }
            else{
                Write-Host "Warning! Orphan file found. This file has no .psbak file." $this.destinationpath
            }#>


            if(!(Test-Path -LiteralPath $this.destinationpath)){
                #destinationpath does NOT exist
                Throw "While cleaning up destination file not found, this should not be possible and might be an error in the script. Aborting script."
            }
            if(!(Test-Path -LiteralPath ($this.sourcepath + ".psbak")) -and (Test-Path -LiteralPath $this.sourcepath)){
                #sourcepath psbak does not exist, but source file exists
                Write-Host "Warning! Source psbak file does not exist, but source file exists. Either you added this file after starting this script, cleaned up before backing up or something went wrong." $this.sourcepath
                $global:FilesWithWarnings.Add($this)
            }
            if(!(Test-Path -LiteralPath ($this.destinationpath +".psbak"))){
                #destinationpath psbak does NOT exist
                Write-Host "Warning! Orphan file was found in destination. Probably because .psbak was manually deleted" $this.destinationpath
                $global:FilesWithWarnings.Add($this)
            }

            if(!(Test-Path -LiteralPath $this.sourcepath)){
                #sourcepath does NOT exist

                if($this.deleteddatetime -ne 0){ #if deletedatetime is not 0. not 0 means it was detected before, 0 means deletion wasnt detected before
                    if(($date - $this.deleteddatetime).TotalDays -gt $global:FileRetentionDays){
                        #file expired retention days
                        Write-Host "Information! File retention has expired. File can be deleted" $this.destinationpath
                        if($global:AllowFileDeletion -eq $true){
                            Write-Host "Deleting file in destination and .psbak in source and destination" $this.destinationpath
                            $global:DeletedBackupFiles.Add($this)
                            Remove-Item -LiteralPath $this.destinationpath
                            Remote-item -LiteralPath ($this.destinationpath + ".psbak")
                            Remove-Item -LiteralPath ($this.sourcepath + ".psbak")
                        }
                        else{
                            Write-Host "File will not be deleted because AllowFileDeletion switch is set to false. Please delete manually!"
                        }
                    }
                    else{
                        #file deleted but retention not expired
                        #Write-Host "File will be deleted after retention expires" $this.destinationpath
                        $global:DeletedSourceFiles.Add($this)
                    }
                }
                else{
                    #deleteddatetime is 0
                    #Write-Host "File deletion detected, adding deleteddatetime" $this.sourcepath
                    $this.deleteddatetime = $date
                    <#if(($date - $this.deleteddatetime).TotalDays -gt $global:FileRetentionDays){
                        #file expired retention days
                        Write-Host "Warning! File retention has expired. File can be deleted" $this.destinationpath
                    }#>
                    $global:DeletedSourceFiles.Add($this)
                    $this | Export-Clixml -LiteralPath ($this.destinationpath + ".psbak") # will overwrite existing psbak
                }
            #Write-Host "Deleting file" $this.destinationpath #temp for fast deletion
            #Remove-Item -LiteralPath $this.destinationpath #temp for fast deletion
            #Remove-item -LiteralPath ($this.destinationpath + ".psbak")#temp for fast deletion
            }
            
            #check
        }
        #start the whole backup process for this file
        backup($destinations){
            #Write-Host "@@@@@Starting backup process for file" $this.sourcepath
            $psbakext = ".psbak"
        
            $this.loadpsbak() #load information from .psbak file to actual file object
            #check if previous backup attempt was aborted and .pslock file is still there
            if(Test-Path -LiteralPath ($this.destinationpath + ".pslock")){
                Write-Host ".pslock found, this means script was ungracefully closed. Deleting destination file and creating new backup"
                Write-Host "Debug DELETING DESTINATIONPATH! Debug / uncomment next line #191"
                #Remove-Item $this.destinationpath
            }


            #create backup because $backedup is false and file does not exist in destinationpath
            if(($this.backedup -eq $false) -and (!(Test-Path -LiteralPath $this.destinationpath))){
                Write-Host "psbak does not exist, no backup existing, creating new backup" $this.sourcepath
                $this.getsourcehash()
                $this.copyfile($destinations)
                $global:NewFiles.Add($this)
                $global:NewHashFiles.Add($this)
            }
            else{
                #Write-Host $this.sourcepath "exists in psbak and destinationpath (1)"
            }

            #create backup because destination from psback does not exist
            if(($this.backedup -eq $true) -and (!(Test-Path -LiteralPath $this.destinationpath))){
                Write-Host $this.sourcepath "Warning. psbak says backedup but destination does not exist! Creating new backup" $this.sourcepath
                $global:FilesWithWarnings.Add($this)
                $this.getsourcehash()
                $this.copyfile($destinations)
                $global:NewFiles.Add($this)
                $global:NewHashFiles.Add($this)
            }
            else{
                #Write-Host $this.sourcepath "exists in psbak and destinationpath (2)"
            }
         
            #check if file and psback exists in source and destination now
            $pathtestarray = @($this.sourcepath,$this.destinationpath,($this.destinationpath + $psbakext),($this.sourcepath + $psbakext))
            ForEach($path in $pathtestarray){
                if(Test-Path -LiteralPath $path){
                    #Write-Host $path "exists after backup"
                }
                else{
                    
                    Throw $path + "does not exist after backup. Critical Error!! " + $this.sourcepath
                }
            }
            #check if hash is expired, generate hash for src, dst, then compare to .psbak(src+dst)
            if((Get-Date).AddDays(-($global:HashExpireDays)) -gt $this.hashdatetime){
                Write-Host $this.sourcepath "Hash expired, generating new one and comparing"
                $global:NewHashFiles.Add($this)
                $sourcehash = (Get-Filehash -Algorithm $global:Algorithm -Path $this.sourcepath).hash
                $destinationhash = (Get-Filehash -Algorithm $global:Algorithm -Path $this.destinationpath).hash
                $sourcepsbakhash = $this.hash
                if(($sourcehash -eq $destinationhash) -and ($sourcehash -eq $sourcepsbakhash) -and ($destinationhash -eq $sourcepsbakhash)){
                    #Write-Host $this.sourcepath "and" $this.destinationpath "hashes do match. no action required. overwriting .psbak because of hash date"
                    $this.hashdatetime = Get-Date
                    Write-Host "debug"
                    $this | Export-Clixml -LiteralPath ($this.sourcepath + ".psbak")
                    $this | Export-Clixml -LiteralPath ($this.destinationpath + ".psbak")
                }
                else{
                    Write-Host $this.sourcepath "or" $this.destinationpath "Warning! hash compare ERROR! manual action required! Hashes did not match" 
                    $global:FilesWithWarnings.Add($this)
                    $msgstring = "PS-Backup Fehler aufgetreten! Hashes stimmen nicht überein! `nQuelle: " + $this.sourcepath + " `nZiel: " + $this.destinationpath
                    MSG Plex /V /Time:3600000 $msgstring
                }
            }
            else{
                #Write-Host $this.sourcepath "hash not expired."
            }
            #check if psbak from source and destination are identical
            $psbacksrc = Import-Clixml -LiteralPath ($this.sourcepath + $psbakext)
            $psbackdst = Import-Clixml -LiteralPath ($this.destinationpath + $psbakext)

            if(($psbacksrc.sourcepath -eq $psbackdst.sourcepath) -and 
                ($psbacksrc.destinationpath -eq $psbackdst.destinationpath) -and
                ($psbacksrc.backedup -eq $psbackdst.backedup) -and
                ($psbacksrc.hashed -eq $psbackdst.hashed) -and
                ($psbacksrc.hash -eq $psbackdst.hash) -and
                ($psbacksrc.hashdatetime -eq $psbacksrc.hashdatetime)
               ){
                    #Write-Host $this.sourcepath "PSBak files do match in src and dst"
               }
               else{
                    Write-Host $this.sourcepath "Warning! PSBakfiles do not match!"
                    $global:FilesWithWarnings.Add($this)
                    $msgstring = "PS-Backup Fehler aufgetreten! Hashes stimmen nicht überein im PSBak File! `nQuelle: " + $this.sourcepath + " `nZiel: " + $this.destinationpath
                    MSG Plex /V /Time:3600000 $msgstring
               }
            #Write hash expire date in console
            #Write-Host "Hash will expire:" (($this.hashdatetime).AddDays(($global:HashExpireDays)))
            #Write-Host ""#newline
        }
        getsourcehash(){
            $source = Get-Filehash -Algorithm $global:Algorithm -Path $this.sourcepath
            #$destination = Get-Filehash -Algorithm SHA256 -Path $this.destinationpath
            <#if($source.hash -eq $destination.hash){
                #hashes do match
                Write-Host "Source and Destination hash do match"
                $this.hash = $destination.hash
                $this.hashed = $true
                $this.hashdatetime = Get-Date
            }#>
            $this.hash = $source.hash
            $this.hashdatetime = Get-Date
            $this.hashed = $true
            #Write-Host "hashed file, set hashedatetime, hashed set true"
        }
        loadpsbak(){
            if(Test-Path -LiteralPath ($this.sourcepath + ".psbak")){
                #psbak exists
                $psbak = Import-Clixml -LiteralPath ($this.sourcepath + ".psbak")
                #check if file was moved
                
                $this.destinationpath = $psbak.destinationpath
                $this.backedup = $psbak.backedup
                $this.hashed = $psbak.hashed
                $this.hash = $psbak.hash
                $this.hashdatetime = $psbak.hashdatetime
                if($psbak.deleteddatetime){
                    $this.deleteddatetime = $psbak.deleteddatetime
                }
                if($this.sourcepath -ne $psbak.sourcepath){
                    #source file not equals psbak file source
                    if($this.sourcepath -ne $psbak.destinationpath){
                        #sourcepath is not equals destinationpath psbak
                        Write-Host "Warning (removing this warning in next version)! File was moved together with .psbak file. Changing sourcepath to new destination." $this.sourcepath #TBD check .pskbak destionation
                        $this | Export-Clixml -LiteralPath ($this.destinationpath + ".psbak")
                        $this | Export-Clixml -LiteralPath ($this.sourcepath + ".psbak")
                        #$global:FilesWithWarnings.Add($this)
                        
                    }
                    else{
                        $this.sourcepath = $psbak.sourcepath
                    }
                    
                }
                else{
                    $this.sourcepath = $psbak.sourcepath
                }
            }
            else{
                #Write-Host $this.sourcepath "psbak file does not exist / .loadpsbak"
            }
        }
        copyfile($destinations){
            $destinationalreadyfound = 0
            $newdestination = ""
            $destinationcount = 0
            $destinationloopcount = 0
            ForEach($destination in $destinations){#count the destinations for the loop after this
                $destinationcount++
            }
            ForEach($destination in $destinations){
                $destinationloopcount++
                if($destinationalreadyfound -lt 1){
                    $driveletter = $destination.Substring(0,1)
                    $diskfreespacebytes = (Get-PSDrive -Name $driveletter).Free
                    $diskfreespaceGB = ($diskfreespacebytes = (Get-PSDrive -Name $driveletter).Free)/1024/1024/1024
                    if($diskfreespaceGB -gt $global:FreeSpaceLimitGB){
                        #Write-Host $driveletter "has enough space. Limit:" $global:FreeSpaceLimitGB
                        $destinationalreadyfound = 1 #cancle ForEach 
                        $newdestination = $destination
                        $filename = Split-Path $this.sourcepath -leaf 
                        $filenamecounter = 0
                        $oldfilename = $filename #for the while loop coming, so it can easily revert to previous filename
                        While(Test-Path -LiteralPath ($newdestination + "\" + $filename)){
                            Write-Host $filename "Information. Destination already exists. Using different Filename!"
                            if($filenamecounter -gt 0 ){
                                $filename = $oldfilename + ".$filenamecounter"
                            }
                            else{
                                $filename = $filename + ".$filenamecounter"
                            }
                            $filenamecounter++
                        }
                        #before copying create filename.pslock to make create a mark on FS that this file is now copying and not finished
                        New-Item -ItemType File -Path ($this.destinationpath + ".pslock") -ErrorAction Stop #stop if file already exists
                        Copy-Item -LiteralPath $this.sourcepath -Destination ($newdestination + "\" + $filename)
                        $this.destinationpath = ($newdestination + "\" + $filename)
                        $this.backedup = $true
                        $this | Export-Clixml -LiteralPath ($this.sourcepath + ".psbak")
                        $this | Export-Clixml -LiteralPath ($this.destinationpath + ".psbak")
                        #delete .pslock file beacsue backup is completed
                        Remove-Item -Path ($this.destinationpath + ".pslock")
                    }
                    else{
                        #Write-Host $driveletter "Does not have enought space"
                        if($destinationloopcount -eq $destinationcount){
                            Throw "No destination has free space, aborting script!"
                        }
                    }
                }
            }
        }
    }
    Class FileLibrary{ # a FileLibrary object contains files
        [string]$libraryname #?name for the FileLibrary object? Used to declare, what the FileLibrary is used for (eg "sourceset" ..)
        [system.array]$filearray #collection of file object class defined earlier. the array consists of System.IO.FileSystemInfo Objects
        FileLibrary ([string]$libraryname){ #overload with name
            $this.libraryname = $libraryname
        }
        FileLibrary ([system.array]$filearray){ #overload with name
            $this.filearray = $filearray
        }
        addfiles($path){ #gets files from filesystem path and adds it to the object. If file has .psbak: information from .psbak is verified then added (verification does not include hash)
            Write-Host "Adding files to library, this may take some time." $path
            $filesarray = @()
            $files = Get-Childitem -Recurse -Path $path -File -Exclude *.psbak,Thumbs.db
            ForEach($file in $files){
                $this.filearray += [File]::new($file.FullName,$false,$false,$null,$null,0,0)            
            }
        }
        backup($destinations){
            Write-Host "Starting backup for filelibrary called" $this.libraryname ", destinations: " $destinations
            ForEach($file in $this.filearray){
                $file.backup($destinations)
            }
        }
        cleanup(){
            Write-Host "Starting cleanup for filelibrary called" $this.libraryname
            ForEach($file in $this.filearray){
                $file.cleanup()
            }
        }
        <#addpsbakfiles($path){ #gets files from filesystem path and adds it to the object. If file has .psbak: information from .psbak is verified then added (verification does not include hash)
            $filesarray = @()
            $files = Get-Childitem -Recurse -Path $path -File -include *.psbak
            ForEach($file in $files){
                $this.filearray += [File]::new($file.FullName,$false,$false,$null,$null,0)            
            }
        }#>
    }
    #> Class Definition

    #< Main
    #Backup
    #Throw ""
    $sourcelibrary = [FileLibrary]::new("source")
    ForEach($path in $Sources){
        $sourcelibrary.addfiles($path)
    }
    Write-Host "Added" $Sources "to library:" $sourcelibrary.libraryname
    $sourcelibrary.backup($Destinations)

    
    #Destination cleanup/checks
    $destinationlibrary = [FileLibrary]::new("destination")
    ForEach($path in $Destinations){
        $destinationlibrary.addfiles($path)
    }
    Write-Host "Added" $Destinations "to to library:" $destinationlibrary.libraryname
    $destinationlibrary.cleanup()

    #>Main
}
Catch{
    Write-Host "Error caught! Check log!"
    MSG Plex /V /Time:3600000 "PS-Backup Fehler aufgetreten! Log überprüfen!"
}

Finally{
    if($error){
        Write-Host "Errors:"
        $error
        $msgstring = "PS-Backup Fehler aufgetreten!`nBitte Log überprüfen und error output analysieren."
        MSG Plex /V /Time:3600000 $msgstring

    }
    Write-Host "---------------------"
    Write-Host "Summary"
    if ($global:NewFiles.Count -gt 0){
        Write-Host "New files:" $global:NewFiles.Count
        Write-Host "---------------------"
        ForEach ($file in $global:NewFiles){
            Write-Host "New file" $file.sourcepath "backedup to" $file.destinationpath
        }
        Write-Host "######################"
    }    
    
    if ($global:NewHashFiles.Count -gt 0){
        Write-Host "New hashes calculated:" $global:NewHashFiles.Count
        Write-Host "---------------------"
        $global:NewHashFiles
        Write-Host "######################"
    }        
    
    if ($global:DeletedSourceFiles.Count -gt 0){
        Write-Host "Files deleted in source:" $global:DeletedSourceFiles.Count
        Write-Host "---------------------"
        ForEach ($file in $global:DeletedSourceFiles){
            Write-Host $file.sourcepath "was deleted" $file.deleteddatetime ". Backup will be deleted on the" ($file.deleteddatetime.AddDays($global:FileRetentionDays))
        }
        Write-Host "######################"
    }        
    
    if ($global:DeletedBackupFiles.Count -gt 0 ){
        Write-Host "Files retention time over" $global:DeletedBackupFiles.Count
        Write-Host "---------------------"
        $global:DeletedBackupFiles
        Write-Host "######################"
    } 
    
    if ($global:FilesWithWarnings.Count -gt 0){
        Write-Host "Files with warnings" $global:FilesWithWarnings.Count
        Write-Host "---------------------"
        $global:FilesWithWarnings
        Write-Host "######################"
    }
    
    Write-Host "@@@@@@@@@@@@@@@"
    Write-Host "New files:" $global:NewFiles.Count
    Write-Host "New hashes calculated:" $global:NewHashFiles.Count
    Write-Host "Files deleted in source:" $global:DeletedSourceFiles.Count
    Write-Host "Files retention time over" $global:DeletedBackupFiles.Count
    Write-Host "Files with warnings" $global:FilesWithWarnings.Count
    Stop-Transcript
    $error.clear()
}