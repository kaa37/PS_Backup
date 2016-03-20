##################################################################################################
# Скрипт резервного копирования данных v0.9b
# 25-12-2014
# Accel
##################################################################################################
#
#Поддерживаются полные и дифференциальные копии (на основе архивного атрибута файлов)
#
#Системные требования: 
#	Windows 7+, 2008+
#	Установленный архиватор 7-Zip (тестировалось на версии 9.30b)
#
#За один запуск скрипта возможно резервное копирование лишь с одного диска
#NTFS-полномочия на данный момент не сохраняются (определяется возможностями архиватора)
#Скрипт должен запускаться от пользователя, имеющего доступ к архивируемым файлам (с правами SYSTEM, Backup Operator и т.п.)

$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"

##################################################################################################
#Начало блока переменных
##################################################################################################

#Название задания архивирования
#Используется в именовании архива и ссылки на теневую копию
#Должно отвечать правилам именования файлов, наличие пробелов не рекомендуется, т.к. не тестировалось
#Пример: $ArchiveTaskName="DiskE"
$ArchiveTaskName="DiskD"

#Путь до диска-источника резервного копирования 
#Перечень целевых папок этого диска определяется отдельно
#Пример: $SrcDrivePath="D:\"
$SrcDrivePath="D:\"

#Путь до целевого диска 
#Пример: $BackupDrivePath="E:\"
$BackupDrivePath="D:\"

#Полный путь до файла со списком папок для архивирования на диске-источнике
#Пример: $SubfoldersToBackupFile = "E:\Backup\src_dirs.txt"
#	* Каждая строка данного файла должна содержать одну папку, которую мы хотим включить в архив
#	* Путь д.б. относительным, т.е. не содержать буквы диска.
#	* например для D:\Files\FilesToBackup в файле должна быть строка Files\FilesToBackup
#	* Кодировка - ANSI
$SubfoldersToBackupFile = "D:\Backup-Temp\ps_backup\src_dirs.txt"

#Путь до временного файла-списка файлов для архивации:
#Пример: $BackupFilesList = "E:\Backup\backup-filelist.txt"
$BackupFilesList = "D:\Backup-Temp\ps_backup\backup-filelist.txt"

#Путь до целевой папки с архивами (В ней не должно быть никаких других файлов, иначе rotation их может удалить! Также лучше не использовать корень диска, а создать хоть одну подпапку.)
#Пример: $ArchiveDstPath = $BackupDrivePath+"Backup\Script backup"
$ArchiveDstPath = $BackupDrivePath+"Backup\Script backup"

#Полный путь до файла журнала задания
#Пример: $ScriptLogFile = "E:\Backup\BackupFiles.log"
$ScriptLogFile = "D:\Backup-Temp\ps_backup\BackupFiles.log"

#Путь до исполняемого файла архиватора 7-Zip
#Пример: $SevenZipExecutablePath = "C:\Program files\7-Zip\7z.exe"
$SevenZipExecutablePath = "C:\Program files\7-Zip\7z.exe"

#Количество дней хранения архива (отсчет ведется с последнего полного бэкапа)
#Пример: $BackupRotationIntervalDays=22
$BackupRotationIntervalDays=22

##################################################################################################
#Конец блока переменных
##################################################################################################


$BackupFilesListTmp = $BackupFilesList+".tmp"
$backuptype=$args[0]
$VSCPath = $BackupDrivePath+"VSC_"+$ArchiveTaskName+"_$(Get-Date -format "yyyyMMdd")"

# Start-Transcript -Создает запись всего сеанса Windows PowerShell или его части в текстовом файле.
# Чтобы остановить запись, используйте командлет Stop-Transcript
# -Path <String> -Задает расположение файла записи. Введите путь к файлу TXT. Подстановочные знаки не допускаются.
Start-Transcript -path $ScriptLogFile

$LogVars=1

if ($LogVars=1) {
	echo "================================================================="
	echo "ArchiveTaskName: $ArchiveTaskName"
	echo "SrcDrivePath: $SrcDrivePath"
	echo "BackupDrivePath: $BackupDrivePath"
	echo "SubfoldersToBackupFile: $SubfoldersToBackupFile"
	echo "BackupFilesList: $BackupFilesList"
	echo "ArchiveDstPath: $ArchiveDstPath"
	echo "ScriptLogFile: $ScriptLogFile"
	echo "SevenZipExecutablePath: $SevenZipExecutablePath"
	echo "VSCPath: $VSCPath"
	echo "BackupRotationIntervalDays: $BackupRotationIntervalDays"
	echo "================================================================="
	}

echo "Backup started at: $(Get-Date)"

##################################################################################################
function BackupFull {
	echo "Backup type: full"
	
	#Создаем теневую копию
	$s1 = (gwmi -List Win32_ShadowCopy).Create($SrcDrivePath, "ClientAccessible")
	$s2 = gwmi Win32_ShadowCopy | ? { $_.ID -eq $s1.ShadowID }
	$d  = $s2.DeviceObject + "\"

	#Создаем на нее ярлык (удалим предыдущий, если остался после прерванной архивации)
	CMD /C rmdir "$VSCPath"
	cmd /c mklink /d $VSCPath "$d"

	#Составляем список папок для архивации
	"" | Set-Content $BackupFilesList
	Get-Content $SubfoldersToBackupFile | Foreach-Object {CMD /C "echo $VSCPath\$_\* >> $BackupFilesList" }
	
	#Создаем массив параметров для 7-Zip
	$Arg1="a"
	$Arg2=$ArchiveDstPath+"\"+$ArchiveTaskName+"_$(Get-Date -format "yyyy-MM-dd")_`(Full`).zip"
	$Arg3="-i@"+$BackupFilesList
	$Arg4="-w"+$ArchiveDstPath
	$Arg5="-mx=3"
	$Arg6="-mmt=on"
	$Arg7="-ssw"
	$Arg8="-scsUTF-8"
	$Arg9="-spf"

	#Зипуем
	& $SevenZipExecutablePath ($Arg1,$Arg2,$Arg3,$Arg4,$Arg5,$Arg6,$Arg7,$Arg8,$Arg9)
	
	Remove-Item $BackupFilesList

	#Если теневые копии имеют необъяснимую тенденцию копиться, лучше удалим их все
	#CMD /C "vssadmin delete shadows /All /Quiet"
	
	#Или можно удалить только конкретную созданную в рамках данного бекапа
	"vssadmin delete shadows /Shadow=""$($s2.ID.ToLower())"" /Quiet" | iex

	#Удаляем ярлык
	CMD /C rmdir $VSCPath

	#Снимаем архивный бит
	Get-Content $SubfoldersToBackupFile | Foreach-Object {CMD /C "attrib -A -H -S $SrcDrivePath$_\* /S /L" }
	
	#делаем rotation
	echo "Rotating old files..."
	CMD /C "forfiles /D -$BackupRotationIntervalDays /S /P ""$ArchiveDstPath"" /C ""CMD /C del @file"""
	}

##################################################################################################	
function BackupDiff {
	echo "Backup type: differential"
	
	#Создаем теневую копию
	$s1 = (gwmi -List Win32_ShadowCopy).Create($SrcDrivePath, "ClientAccessible")
	$s2 = gwmi Win32_ShadowCopy | ? { $_.ID -eq $s1.ShadowID }
	$d  = $s2.DeviceObject + "\"

	#Создаем на нее ярлык (удалим предыдущий, если остался после прерванной архивации)
	CMD /C rmdir $VSCPath
	cmd /c mklink /d $VSCPath "$d"
	
	#Включаем UTF-8
	CMD /C "chcp 65001 > nul"
	
	#Составляем список файлов, измененных с момента предыдущей архивации
	"" | Set-Content $BackupFilesList
	Get-Content $SubfoldersToBackupFile | Foreach-Object {CMD /C "dir $VSCPath\$_ /B /S /A:A >> $BackupFilesList" }
	
	CMD /C "chcp 866 > nul"
	
	$SearchPattern="^"+$BackupDrivePath.Substring(0,1)+"\:\\"
	
	#Отрезаем букву диска, иначе 7-zip при архивации по списочному файлу глючит, находя несуществующие дубли
	#(Get-Content $BackupFilesList) -replace $SearchPattern,'' > $BackupFilesListTmp
	Get-Content $BackupFilesList | ForEach-Object { $_ -replace $SearchPattern,"" } | Set-Content ($BackupFilesListTmp)
	
	Remove-Item $BackupFilesList
	Rename-Item $BackupFilesListTmp $BackupFilesList
	
	#Поскольку имя диска в путях удалили, нужно перейти в нужную директорию
	cd $BackupDrivePath

	#Создаем массив параметров для 7-Zip
	$Arg1="a"
	$Arg2=$ArchiveDstPath+"\"+$ArchiveTaskName+"_$(Get-Date -format "yyyy-MM-dd")_`(Diff`).zip"
	$Arg3="-i@"+$BackupFilesList
	$Arg4="-w"+$ArchiveDstPath
	$Arg5="-mx=3"
	$Arg6="-mmt=on"
	$Arg7="-ssw"
	$Arg8="-scsUTF-8"
	$Arg9="-spf"

	#Зипуем
	& $SevenZipExecutablePath ($Arg1,$Arg2,$Arg3,$Arg4,$Arg5,$Arg6,$Arg7,$Arg8,$Arg9)
	
	Remove-Item $BackupFilesList

	#Если теневые копии имеют необъяснимую тенденцию копиться, лучше удалим их все
	#CMD /C "vssadmin delete shadows /All /Quiet"
	
	#Или можно удалить только конкретную созданную в рамках данного бекапа
	"vssadmin delete shadows /Shadow=""$($s2.ID.ToLower())"" /Quiet" | iex

	#Удаляем ярлык
	CMD /C rmdir $VSCPath
	}

##################################################################################################	
if ($backuptype -eq "diff") {
	BackupDiff | Out-Host
	}
elseif ($backuptype -eq "full") {
	BackupFull | Out-Host
	}
else {
	echo $backuptype
	echo "None backup type parameter passed! Usage: scriptname.ps1 [ full | diff ]"
	}

echo "Backup finished at: $(Get-Date)"

Stop-Transcript