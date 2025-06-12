#!/bin/sh
#
#
#-------------------------------------------------------------------------------

# Variables
Version="Version 7 du 06/011/2015"
RepSrc="/var/adm/Bck-ladhyx"
PrefixConfFile="bck-rsync-*.ini"
FileInfo=last.txt
InfoTaille=InfoTaille.txt

#-------------------------------------------------------------------------------
#13/05/02------------------------ TransLiteral ---------------------------------
#-------------------------------------------------------------------------------
# Retourne $1 literale (i.e. en minuscules et caracteres [a-z] seulement)

TransLiteral () {
echo `echo $1 | sed -e \
  "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/" \
  -e "s/[^a-z]//g"`
}
#-------------------------------------------------------------------------------
#-------------------------------- CodeErreur -----------------------------------
#-------------------------------------------------------------------------------
# Retourne $1 literale (i.e. en minuscules et caracteres [a-z] seulement)

CodeErreur () {

case "$Err" in
 1  ) Message="Code erreur 1: Fichier de configuration non lisible";;
 2  ) Message="Code erreur 2: Erreur dans le fichier de configuration";;
 3  ) Message="Code erreur 3: Machine non definie dans /etc/hosts";;
 4  ) Message="Code erreur 4: Machine non connectee sur le reseau";;
 5  ) Message="Code erreur 5: L'espace utilise est superieur au QuotaBck";;
 6  ) Message="Code erreur 6: Erreur Rsync !";;
 7  ) Message="Code erreur 7: Pas de sauvegarde car le Quota est depasse";;
 8  ) Message="Code erreur 8: Erreur de creation du dossier dans $RepBck/$NomMachine";;
 9  ) Message="Code erreur 9: Impossible de copier le fichier ($RepSrc/skel/excludes-$TypeMachine.txt)";;
 10 ) Message="Code erreur 10: Erreur de recuperation du fichier de config <rsynd.conf>";;
 11 ) Message="Code erreur 11: Erreur Rsync : access denied ! ";;
 12 ) Message="Code erreur 12: Erreur de lecture des modules dans rsynd.conf";;
 13 ) Message="Code erreur 13: Erreur de lecture log rsync dans bck0_info.txt";;
 14 ) Message="Code erreur 14: Erreur de parametre d'entree: <nom de la machine a sauvegarder>";;
 15 ) Message="Code erreur 15: Erreur une autre sauvegarde est deja en cours";;
 *  ) Message="Code erreur : $Err";;
esac
}
#-------------------------------------------------------------------------------
#-------------------------------- AfficheVar -----------------------------------
#-------------------------------------------------------------------------------
# Pour le debogage

AfficheVar () {
echo "NomMachine : $NomMachine"
echo "TypeMachine : $TypeMachine"
echo "QuotaImg : $QuotaImg"
echo "QuotaBck : $QuotaBck"
echo "NbMaxBck : $NbMaxBck"
echo "JoursActifs : $JoursActifs"
echo "FreqBck : $FreqBck"
echo "FileExclude : $FileExclude"
echo "LstModules : $LstModules"
echo "MailAdr : $MailAdr"
echo "MacAdr : $MacAdr"
echo "RepBck : $RepBck"
echo "OkPourBck : $OkPourBck"
}
#-------------------------------------------------------------------------------
#----------------------------------- ValAbs ------------------------------------
#-------------------------------------------------------------------------------
# Calcul de la valeur absolue d'une difference

ValAbs ()
{
if [ "$1" -ge 0 ]; then absval=$1; else absval=$(( 0 - $1 )); fi
echo $absval
}

#-------------------------------------------------------------------------------
#------------------------------ TailleRsyncDryRun ------------------------------
#-------------------------------------------------------------------------------
# Calcul la taille d'un dossier ($1) via rsync (plus rapide que du -sm)
# Attention les hard-links sont comptes a la taille du chichier...                               


TailleRsyncDryRun ()
{
TmpVal=`rsync -a --stats --dry-run $1 /tmp 2>/dev/null | \
	 sed -e "/^total /s/,//g" | \
	 awk '/^total size is / {printf "%d",$4/1000000}'`
echo $TmpVal
}

#-------------------------------------------------------------------------------
#------------------------------- ArretDistant ----------------------------------
#-------------------------------------------------------------------------------
# Sur le serveur de sauvegarde (client rsync)
# ssh-keygen -t rsa -f clef-bck (==> clef-bck et clef-bck.pub)
# sur les clients :
#   cat clef-bck.pub >> authorized_keys
#   firewall add portopening protocol=TCP port=22 NAME="sshd-cygwin"....etc

ArretDistant () {

HostName="$NomMachine.polytechnique.fr"

if [ "$TypeMachine" = "windows" ]; then
 ssh -q -o StrictHostKeyChecking=no -i $RepSrc/clef-bck \
     -l root $HostName "shutdown.exe /s /f /t 2" > shutdown.log 2>&1
fi

if [ "$TypeMachine" = "linux" ]; then
 ssh -q -o StrictHostKeyChecking=no -i $RepSrc/clef-bck \
     -l root $HostName "/sbin/shutdown -h now" > shutdown.log 2>&1
fi

}
#-------------------------------------------------------------------------------
#----------------------------------- TestRsync ---------------------------------
#-------------------------------------------------------------------------------
# Check du port 873 de rsync via la cmd nc (-w 1 <==> timeout 1 sec)
# NB avec telnet on ne peut pas choisir facilement le timeout.
# Renvoie 0 si ok, 1 si Ko 
# Usage  : $NomMachine doit etre dans /etc/hosts

TestRsync ()
{
if  nc -w 1 $AdrIP 873 > /dev/null 2>&1; then
  return 0
else
  return 1
fi
}

#-------------------------------------------------------------------------------
#--------------------------------- TestRsyncEtWol ------------------------------
#-------------------------------------------------------------------------------
# On test sur le port rsync (873) si la machine repond, sinon et essaie de la
# reveiller puis de la demarrer. Une machine windows peut etre dans 4 etats : 
# marche, arret, veille ou veille prolongee (suspend to disk).
# On teste d'abord la sortie de veille (timeout=60 sec) ensuite on essaie de
# demarrer en testant toutes les 5 (sec) la reponse de rsync avec (timeout=48
# soit 48*5 => 4min). Si on a demarre une machine via la cmd wol il faudra
# l'eteindre apres le bck ==> variable StartMachine=1. sinon Err=4.

TestRsyncEtWol ()
{

# Si la machine est en veille on essaie de la reveiller !
timewait=60; count=1
while ! TestRsync && [ $count -le $timewait ]; do
 count=$(($count+1))
done

# Si Rsync ne repond tjs pas on essaie de demarrer !
if ! TestRsync && [ -n "$MacAdr" ]; then 
 wol $MacAdr > /dev/null 2>&1
 timewait=48; count=1
 
 while ! TestRsync && [ $count -le $timewait ]; do
  count=$(($count+1))
  sleep 4
 done
 
 if TestRsync; then StartMachine=1; else Err=4; fi
fi
} 

#-------------------------------------------------------------------------------
#--------------------------------- ModifLogRsync -------------------------------
#-------------------------------------------------------------------------------
# Le 21/05/2015 2 versions de rsync au labo (3.0.9 et 3.1.1 Suse 12.3 et 13.2)
# Les outputs de l'option stats (rsync.log) n'ont pas le meme format !!!!
# ici on uniformise pour qlqs parametres dans le fichier tmp-info.log....

ModifLogRsync () {

sed -e "/^Number /s/,//g" -e "/^Total /s/,//g" -e "/^total /s/,//g" -e "s/^Number of regular files transferred/Number of files transferred/" rsync.log > tmp-info.log
}

#-------------------------------------------------------------------------------
#------------------------------- LectFichierConf -------------------------------
#-------------------------------------------------------------------------------
# Lecture du ou des fichiers de configuration ($FileConf)
#
# ** Si le nom du fichier de config ($1/$FileConf) est incomplet (i.e sans 
# extension '.ini', ex: bck-rsync-) on lit tous les fichiers bck-rsync-*.ini !
#
# ** Si un nom de machine est donne sur la ligne de commande ($2/$VarMachine)
# --> On sauvegarde que celle-ci si trouvee dans le/les fichiers indiques...
#
# Enregistrement dans une varible ($ConfigMachines) du contenu du/des fichiers.
# avec suppression des lignes vides, espaces, tabilations et commentaires (#).
# Creation d'une liste/index ($IndexMachines) des numeros des lignes de debut
# de section pour chaque machine (ex:1-12-23-34-).

LectFichierConf () {

if [ -n "$FileConf" ]; then
  tmp=${FileConf##*\.} # dernier suffixe (.xxx) du nom contenu dans $FileConf
  
  # Si pas d'extension .ini on lit tous les fichiers FileConf*.ini !
  if [ "$tmp" != "ini" ]; then tmp=${FileConf%\.}; FileConf=$tmp"*.ini"; fi
  
  tmp=`ls -1 $RepSrc/$FileConf 2>/dev/null | head -1 | sed -e "s/^.*\///"`
    
  if [ -n "$tmp" ] && [ -r $RepSrc/$tmp ]; then
    ConfigMachines="`cat $RepSrc/$FileConf | tr -d '\t' | tr -d ' ' | grep -vE '^#|^$'`"
    tmp="`echo "$ConfigMachines" | \
      grep -nE '^NomMachine=' | awk -F':' '{print $1}' | tr -s '\n' '-'`"
       
    LigneFin=`echo "$ConfigMachines" | nl | tail -1 | awk '{printf "%d",$1}'`
    LigneFin=$(($LigneFin + 1))
    IndexMachines=$tmp$LigneFin"-"
  else
    Err=1
  fi
  
  if [ -z "$Err" ] && [ -n "$VarMachine" ]; then
    # modif de la liste IndexMachines pour la machine $VarMachine uniquement !
    IDM=`echo "$ConfigMachines" | grep -nE "^NomMachine=$VarMachine" \
                                | awk -F':' '{print $1}' | tr -s '\n' '-'`
    IDM=${IDM%%-*}
    tmp=${IndexMachines##*$IDM-}
    IndexMachines=$IDM"-"${tmp%%-*}"-"
    if [ "$IndexMachines" = "--" ]; then Err=14; fi 
  fi
fi

}

#-------------------------------------------------------------------------------
#------------------------------ LectureSection ---------------------------------
#-------------------------------------------------------------------------------
# Lecture des parametres de sauvegarde dans $ConfigMachines. La lecture se fait
# a partir des parametres : ligne de debut ($1), ligne de fin ($2)
#
# Le 24/05/2013 Il faut tester la syntaxe de tail car pas la meme entre mandriva
# et OpenSuse 12.3 : tail +x  (Mdv) tail -n +x (Suse)
#
LectureSection () {

# Initialisation des variables
NomMachine=""; TypeMachine=""; QuotaImg=""; QuotaBck=""; NbMaxBck=""; LstModules=""
JoursActifs=""; FreqBck=""; FileExclude=""; MailAdr=""; MacAdr=""; RepBck=""

# Nombre de ligne de la section
nbl=$(($2 - $1))

# Test de la syntaxe du tail (difference entre OpenSuse 12.3 et Mdv) et lecture le section
if [ -z "`echo "$ConfigMachines" | tail +1 2>&1 1>/dev/null`" ]; then
   Section=`echo "$ConfigMachines" | tail +$1 | head -$nbl`
else
   Section=`echo "$ConfigMachines" | tail -n +$1 | head -$nbl`
fi

# Enregistrement des variables
tmp=`echo "$Section" | awk -F '=' '/^NomMachine/ {print $2}'`
NomMachine=`TransLiteral "$tmp"`
tmp=`echo "$Section" | awk -F '=' '/^TypeMachine/ {print $2}' | grep -E 'windows|linux|mac'`
TypeMachine=`TransLiteral "$tmp"`
QuotaImg=`echo "$Section" | awk -F '=' '/^QuotaImg/ {print $2}' | sed -e "s/[^0-9]//g"`
QuotaBck=`echo "$Section" | awk -F '=' '/^QuotaBck/ {print $2}' | sed -e "s/[^0-9]//g"`
NbMaxBck=`echo "$Section" | awk -F '=' '/^NbMaxBck/ {printf "%d",$2}' | sed -e "s/[^0-9]//g"`
JoursActifs=`echo "$Section" | awk -F '=' '/^JoursActifs/ {print $2}' | sed -e "s/[^1-7]//g"`
FreqBck=`echo "$Section" | awk -F '=' '/^FreqBck/ {print $2}' | sed -e "s/[^1-7]//g" -e "s/^\(.\).*/\1/"`
FileExclude=`echo "$Section" | awk -F '=' '/^FileExclude/ {print $2}' | sed -e "s/[^0-1]//g" -e "s/^\(.\).*/\1/"`
tmp=`echo "$Section" | awk -F '=' '/^MailAdr/ {print $2}'`
MailAdr=`TransLiteral "$tmp"`
MacAdr=`echo "$Section" | awk -F '=' '/^MacAdr/ {print $2}'`
RepBck=`echo "$Section" | awk -F '=' '/^RepBck/ {print $2}'`
LstModules=`echo "$Section" | awk -F '=' '/^LstModules/{print $2}' | tr -s ',' '\n' | sed -e 's/\[\(.*\)\]/\1/' | tr -s '\n' '|'`


# Les variables doivent etre toutes non vides sauf eventuellement $MailAdr et $MacAdr
if [ -z "$NomMachine" ] || [ -z "$TypeMachine" ] || [ -z "$QuotaImg" ]; then Err=2; fi
if [ -z "$QuotaBck" ] || [ -z "$JoursActifs" ] || [ -z "$FreqBck" ]; then Err=2; fi
if [ -z "$FileExclude" ] || [ -z "$NbMaxBck" ] || [ -z "$RepBck" ]; then Err=2; fi
if [ "$LstModules" = "|" ]; then LstModules=""; fi

# Verification du nom de machine dans /etc/hosts
AdrIP=`cat /etc/hosts | tr -s '\t' ' ' | grep -F " $NomMachine.polytechnique.fr" | awk '{print $1}'`
if [ -z "$AdrIP" ]; then Err=3; fi

}

#-------------------------------------------------------------------------------
#------------------------------- VerifConfMachine ------------------------------
#-------------------------------------------------------------------------------
# Analyse de la configuration d'une machine a sauvegarder. Positionnement des
# variables: OkPourBck (i.e config ok et jour/frequence ok) et Err 

VerifConfMachine () {

JourSe=`date '+%u'`
JourAn=`date '+%j' | sed -e "s/^0*//"`
OkPourBck=1

# Si le repertoire $RepBck/bck/$NomMachine n'existe pas, on le cree et on se place dedans.
RepBck="$RepBck/bck"
if [ ! -e $RepBck/$NomMachine ] && ! mkdir -p $RepBck/$NomMachine > /dev/null 2>&1; then Err=8; fi
cd $RepBck/$NomMachine > /dev/null 2>&1

# JourAct est non vide si le jour courant est compris dans $JoursActifs
JourAct=`echo $JoursActifs | sed -e "s/[^$JourSe]//g"`
if [ -z "$Err" ] && [ -z "$JourAct" ]; then OkPourBck=0; fi

# Lecture dans $FileInfo du jour de la derniere sauvagarde
JourDerBck=""
if [ -z "$Err" ] && [ -r "$FileInfo" ]; then
  JourDerBck=`cat $FileInfo | grep -E '^JourDernierBck' | awk -F'=' '{printf"%d",$2}'`
fi
if [ -n "$JourDerBck" ] && [ $JourDerBck -eq $JourAn ]; then OkPourBck=0; fi 

# FreqBck avec le pb des annees bissextiles
# si la difference en valeur absolue entre le jours de l'annee et le dernier
# jour de bck est strictement inferieure a la freqence il n'y a pas de bck. 
Bissex=0; Derfev=`cal 02 $An | tr -s ' ' '\n' | tail -1`; if [ $Derfev -eq 29 ]; then Bissex=1; fi
if [ -z "$Err" ] && [ -n "$JourDerBck" ]; then
  if [ $JourDerBck -eq 365 ] && [ $Bissex -eq 0 ]; then JourDerBck=0; fi
  if [ $JourDerBck -eq 366 ]; then JourDerBck=0; fi
  if [ `ValAbs $(($JourAn - $JourDerBck))` -lt $FreqBck ]; then OkPourBck=0; fi
fi

# Si la variable $FileExclude est active et que le fichier 
# $RepBck/$NomMachine/excludes.txt n'existe pas on le cree (copie depuis $RepSrc/skel).
if [ -z "$Err" ] && [ "$FileExclude" = "1" ] && [ ! -r excludes.txt ] \
   && (! cp $RepSrc/skel/excludes-$TypeMachine.txt excludes.txt  > /dev/null 2>&1); then
 Err=9
fi
}

#-------------------------------------------------------------------------------
#---------------------------------- OptionsRsync -------------------------------
#-------------------------------------------------------------------------------
# Positionnement des options rsync en fonction du type de machine....

OptionsRsync () {

Excl=""; OptsWin=""

if [ "$TypeMachine" = "windows" ]; then
  #Export Variables pour la gestion charset iconv
  LANG=fr_FR.UTF-8
  LC_CTYPE=fr_FR.UTF-8
  LC_NUMERIC=fr_FR.UTF-8
  LC_TIME=fr_FR.UTF-8
  LC_COLLATE=fr_FR.UTF-8
  LC_MONETARY=fr_FR.UTF-8
  LC_MESSAGES=fr_FR.UTF-8
  LC_PAPER=fr_FR.UTF-8
  LC_NAME=fr_FR.UTF-8
  LC_ADDRESS=fr_FR.UTF-8
  LC_TELEPHONE=fr_FR.UTF-8
  LC_MEASUREMENT=fr_FR.UTF-8
  LC_IDENTIFICATION=fr_FR.UTF-8
  export LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
  export LC_PAPER LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION
  OptsWin="--modify-window=1 --iconv=. --chmod=u+rwx --fake-super"
fi

if [ "$FileExclude" = "1" ]; then Excl="--exclude-from=excludes.txt"; fi

RsyncOpts="-av --stats --delete $OptsWin $Excl $AdrIP"

}

#-------------------------------------------------------------------------------
#---------------------------------- LectConfDist -------------------------------
#-------------------------------------------------------------------------------
# Si LstModules n'est pas defnit dans le fichier .ini (i.e. LstModules=""), 
# Recuperation via rsync du fichier de configuration distant (rsynd.conf) et
# creation de la liste des modules a sauvegarder...
# Windows : c:\ICW\rsyncd.conf
# Linux   : /etc/rsyncd.conf
# MacOS   : xxxxxx

LectConfDist () {

# Initialisations
OptsWin=""

# On se place dans le repertoire de sauvegarde de la machine
cd $RepBck/$NomMachine

if [ -z "$LstModules" ]; then
# Rsync avec Options
OptionsRsync
RsyncOpts="-av --delete $OptsWin $AdrIP"
Module="Config"
(rsync $RsyncOpts::$Module/rsyncd.conf . > /dev/null) >& Err_rsync.log

# Erreur si la taille de Err_rsync.log est superieur a zero !
# Sinon extraction de la liste des modules sous la forme : module1|module2|...|
if [ -s Err_rsync.log ]; then
  if [ -n "`grep 'access denied' Err_rsync.log`" ]; then
   Err=11
  else 
   Err=10
  fi
else
  LstModules="`cat rsyncd.conf | tr -d '\015' | tr -d '\t' | tr -d ' ' | grep -E '^\[' | \
                grep -Ev '^\[Config\]' | sed -e 's/\[\(.*\)\]/\1/' | tr -s '\n' '|'`"
  if [ -z "$LstModules" ]; then Err=12; fi
fi

fi
}

#-------------------------------------------------------------------------------
#----------------------------------- VerifQuota --------------------------------
#-------------------------------------------------------------------------------
# On supprime des increments tant que le QuotaBck (quota global) est depasse 
# ou que le nombre max de bck est atteint.
# Si  $NbMaxBck > 0 ==> politique de quota NombreMax et quotaImg
# Sinon             ==> politique du quota global et QuotaImg (! du -sm !)
# NB execution ssi bck0 existe (cf le premier if) !

VerifQuota () {

cd $RepBck/$NomMachine

if [ -d bck0 ]; then
  # Numero du dernier bck (bckx et n=x)
  n=`ls -d1 bck* | sed -e 's/bck//g' -e 's/\///g' | sort -n | tail -1`
 
  # Mise en variable du Contenu du fichier $InfoTaille
 InfoDu="`cat "$InfoTaille"`"

 if [ "$NbMaxBck" -gt 0 ]; then
 # Cas Nombre limite de bck
 tmp=$(($NbMaxBck - 1))
   while [ "$n" -ge "$tmp" ]; do
     \rm -rf bck$n; \rm -f info_bck$n.txt
     InfoDu=`echo "$InfoDu" | grep -vE "^bck$n:"`
     n=$(($n - 1))
   done
 # Cas QuotaBck ==> 'du -sm' et suppression des bckX tant que le QuotaBck est depasse.
 else
   TailleDu=`du -sm | awk '{printf"%d",$1}'`
   while [ "$QuotaBck" -lt "$TailleDu" ] && [ "$n" -gt 0 ]; do
     \rm -rf bck$n; \rm -f info_bck$n.txt
     InfoDu=`echo "$InfoDu" | grep -vE "^bck$n:"`
     TailleDu=`du -sm | awk '{printf"%d",$1}'`
     n=$(($n - 1))
   done
   if [ "$QuotaBck" -lt "$TailleDu" ]; then Err=5; fi
 fi
 
 # Ecriture du nouveau fichier $InfoTaille
 echo "$InfoDu" > $InfoTaille
fi
}

#-------------------------------------------------------------------------------
#-------------------------------- RotationDesBcks ------------------------------
#-------------------------------------------------------------------------------
# Rotation des sauvegardes (bck2-->bck3, bck1-->bck2...etc)

RotationDesBcks () {

if [ -d bck0 ]; then
  # numero du dernier bck (bckx et n=x)
  n=`ls -d1 bck* | sed -e 's/bck//g' -e 's/\///g' | sort -n | tail -1`

  while [ "$n" -gt 0 ]; do
    NPlusUn=$(($n + 1))
    mv bck$n bck$NPlusUn
    mv info_bck$n.txt info_bck$NPlusUn.txt
    InfoDu=`echo "$InfoDu" | sed -e "s/^bck$n:/bck$NPlusUn:/"`
    n=$(($n - 1))
  done
fi
}

#-------------------------------------------------------------------------------
#---------------------------------- EcritureLog --------------------------------
#-------------------------------------------------------------------------------
# Formatages et ecriture des infos : d'execution, de date, d'heure...etc
# Ecriture dans 2 fichiers info_bck0.txt et $FileInfo. 

EcritureLog () {

if [ "$1" = "Debut" ]; then
  echo "Date : `date`" > info_bck0.txt
  echo "Machine : $NomMachine" > $FileInfo
  echo -e "Date : `date '+%d/%m/%Y'`\n" >> $FileInfo
  echo "Heure de debut : `date '+%H:%M:%S'`" >> $FileInfo
fi

if [ "$1" = "Stats" ]; then
  # Ecriture des info de taille lues dans les stats de rsync
  Ttotal="`awk '/^total size is / {printf "%.2f Mo",$4/1000000}' tmp-info.log`"
  Tincrt="`awk '/^Total transferred file size:/ {printf "%.2f Mo",$5/1000000}' tmp-info.log`"
  echo "Sauvegarde du Module : $Module (Total: $Ttotal / Increment: $Tincrt)" >> $FileInfo
  cat tmp-info.log >> info_bck0.txt
fi

if [ "$1" = "Fin" ]; then
  # Ecriture dans le fichier d'info
  echo "Heure de fin   : `date '+%H:%M:%S'`" >> $FileInfo
  echo "" >> $FileInfo; echo "JourDernierBck=$JourAn" >> $FileInfo
  echo "Options de sauvegarde : $RsyncOpts" >> $FileInfo
  if [ "$FileExclude" = "1" ]; then
    echo "" >> $FileInfo
    echo "-----------------------------------------------------" >> $FileInfo
    echo "Liste des fichiers exclus de la sauvegarde : " >> $FileInfo
    cat excludes.txt >> $FileInfo
    echo "-----------------------------------------------------" >> $FileInfo
  fi
fi
}

#-------------------------------------------------------------------------------
#----------------------------------- VerifBackup -------------------------------
#-------------------------------------------------------------------------------
# Verification du backup apres BckMachine. Calcul des tailles: totale, increment
# et nombre de fichiers. verification des qutas/nombre de bck...etc 

VerifBackup () {

Ttotal=`awk 'BEGIN {n=0} /^total size is / {n=n+$4} END {printf "%d",n/1000000}' info_bck0.txt`
Tincrt=`awk 'BEGIN {n=0} /^Total transferred file size:/ {n=n+$5} END {printf "%d",n/1000000}' info_bck0.txt`
NBfile=`awk 'BEGIN {n=0} /^Number of files transferred:/ {n=n+$5} END {printf "%d",n}' info_bck0.txt`
#NBfile=`cat info_bck0.txt | grep -E '^Number of files transferred:' |  awk 'BEGIN {n=0} {n=n+$5} END {printf "%d",n}'`

# Cas Erreur Rsync dans BckMachine on conserve le bck si plus grand que bck n-1
if [ $Ttotal -eq 0 ] && [ "$Err" = "6" ]; then
  TBckOld=0; TBckNew=0
  if [ -d tmp-bck ] && [ -d bck0 ]; then
    TBckOld=`du -sm tmp-bck | awk '{printf"%d",$1}'`
    TBckNew=`du -sm bck0 | awk '{printf"%d",$1}'`
  fi
  if [ $TBckNew -gt $TBckOld ]; then Ttotal=$TBckNew; fi
fi

# On teste le bck (quota, absence de tranfert, suppression...) 
# si ok rotations, sinon suppression et/ou renvoie d'erreur
if [ $Ttotal -gt 0 ] && [ $Ttotal -lt $QuotaImg ]; then
  
  # On teste si $NBfile > 0 ou 'deleting non nul'
  # ==> nouveau bck et rotation des images !
  if [ $NBfile -gt 0 ] || [ -n "`grep -E '^deleting ' info_bck0.txt`" ]; then
    # Ecriture dans $InfoDu/$InfoTaille:
    # bckx:Taille Total:Taille Increment:Nombre De Fichiers
    InfoDu=`echo -e "bck0:$Ttotal:$Tincrt:$NBfile\n$InfoDu"`
    
    RotationDesBcks
    
    if [ -d tmp-bck ]; then
      \mv tmp-bck bck1; \mv -f info_tmp-bck.txt info_bck1.txt
      InfoDu=`echo "$InfoDu" | sed -e 's/^tmp-bck/bck1/'`
    fi
  
  # Sinon pas d'increment et pas de suppression
  # ==> pas de nouveau bck
  else
    OkPourBck=2;
    if [ -d tmp-bck ]; then
      \rm -rf bck0; \rm info_bck0.txt
      \mv tmp-bck bck0; \mv -f info_tmp-bck.txt info_bck0.txt
      InfoDu=`echo "$InfoDu" | sed -e 's/^tmp-bck/bck0/'`
    fi
  fi

# Sinon le QuotaImg est depasse ou bien Err=13 (erreur lecture dans log rsync)
# on supprime les fichiers tranferes...
else
  if [ -z "$Err" ]; then Err=7; fi
  if [ -z "$Err" ] && [ $Ttotal -eq 0 ]; then Err=13; fi

  if [ -d tmp-bck ]; then
    \rm -rf bck0; \rm info_bck0.txt
    \mv tmp-bck bck0; \mv -f info_tmp-bck.txt info_bck0.txt
    InfoDu=`echo "$InfoDu" | sed -e 's/^tmp-bck/bck0/'`
  fi
fi

}

#-------------------------------------------------------------------------------
#------------------------------- TestBckEnCours ------------------------------
#-------------------------------------------------------------------------------
# Si le dossier tmp-bck il y a deja un autre bck en cours

TestBckEnCours () {

if [ -d $RepBck/$NomMachine/tmp-bck ]; then Err=15; fi

}

#-------------------------------------------------------------------------------
#---------------------------------- BckMachine ---------------------------------
#-------------------------------------------------------------------------------
# La sauvegarde par rsync se fait tjs par rapport a bck0. Si elle est correcte
# (pas d'erreur rsync, quota...) on la conserve et on lance la rotation des
# numeros des auvegardes (bck2-->bck3, bck1-->bck2...etc)

BckMachine () {

# Initialisation des variables et des fichiers de log
RsyncOpts=""
echo "" > tmp-err.log
echo "" > Err_rsync.log

# On se place dans le repertoire de sauvegarde de la machine $NomMachine
cd $RepBck/$NomMachine

# Si bck0 existe cp -al dans tmp-bck et modification dans $InfoTaille
# sinon creation du dossier bck0
if [ -d bck0 ]; then
  # Mise en variable du Contenu du fichier $InfoTaille
  InfoDu="`cat $InfoTaille`"
  cp -al bck0 tmp-bck
  \mv -f info_bck0.txt info_tmp-bck.txt
  InfoDu=`echo "$InfoDu" | sed -e 's/^bck0/tmp-bck/'`
else
  mkdir bck0
  InfoDu=""
fi

# Positionnement des options Rsync
OptionsRsync

# Ecriture des log ('Debut')
EcritureLog "Debut"

# RSYNC : tant que la liste des modules n'est pas vide on la parcourt
while [ -n "$LstModules" ]; do
  # Execution du Rsync et ecriture des log info et erreur
  Module=${LstModules%%\|*}; tmp=${LstModules#*\|}; LstModules=$tmp
  echo -e "\n***** Bck Module: $Module\n" >> info_bck0.txt
  (rsync $RsyncOpts::$Module/ bck0/$Module/ > rsync.log) >& tmp-err.log
  
  ModifLogRsync
  
  # Si rsync renvoie une erreur
  if [ -s tmp-err.log ]; then
    echo -e "\n***** Err Module: $Module\n" >> Err_rsync.log
    cat tmp-err.log >> Err_rsync.log
    echo "" > tmp-err.log; Err=6
  fi
  # Ecriture des log ('stats') de rsync
  EcritureLog "Stats"
done

# Ecriture des logs 'Fin'
EcritureLog "Fin"

# Verification du backup
VerifBackup

# Ecriture du nouveau fichier $InfoTaille
echo "$InfoDu" | sort > $InfoTaille
}

#-------------------------------------------------------------------------------
#-------------------------------- EnvoiMail ------------------------------------
#-------------------------------------------------------------------------------
# Envoi d'un mail via le script CGI disponible sur Ladhyx afin d'eviter 
# d'activer postfix ou sendmail en null-client sur la machine de sauvegarde.
#
# $1 le sujet
# $2 le ou les destinataires  
# EnvoiMail "sujet du mail" sauvegarde

EnvoiMail () {

Message=""
cd $RepBck/$NomMachine

# Mise en forme du corps du message, du Sujet et des destinataires
Dest="sauvegarde"

if [ -n "$MailAdr" ]; then Dest="$MailAdr sauvegarde"; fi

if [ -n "$Err" ]; then
  CodeErreur
  Sujet="** ERREUR ** Bck incremental $NomMachine"
else 
  Message="`cat $FileInfo`\n"
  Sujet="Bck incremental de $NomMachine"
fi

# Cas rien de nouveau a sauvegarder
if [ -z "$Err" ] && [ $OkPourBck -eq 2 ]; then
  tmp="`date '+%d/%m/%Y'`"
  Message=`echo -e "Machine : $NomMachine\n$tmp\n\nRien de nouveau a sauvegarder !\n"`
fi

# Calcul du nombre de backup
if [ -d bck0 ]; then
  n=`ls -d1 bck* | sed -e 's/bck//g' -e 's/\///g' | sort -n | tail -1`
  NbBck=$(($n + 1))
fi

if [ -z "$Err" ]; then
  Message="$Message\n\nLimite de taille pour une sauvegarde : $QuotaImg Mo"
  Ttotal="`awk 'BEGIN {n=0} /^total size is / {n=n+$4} END {printf "%.2f",n/1000000}' info_bck0.txt`"
  Message="$Message\nTaille totale de la derniere sauvegarde : $Ttotal Mo"
fi

Message="$Message\n\nNombre de sauvegardes : $NbBck"
Host="`hostname -s`"; Message="$Message\nMachine de sauvegarde : $Host"
Message="$Message\nScript bck-rsync.sh ($Version)"
if [ $StartMachine -eq 1 ] && [ -e shutdown.log ] && [ ! -s shutdown.log ]; then
 Message="$Message\nNB Demarrage puis arret de la machine apres la sauvegarde."
fi

## Mise en forme et Envoi du mail 
Host="`hostname`"
Tmp="$Message|$Sujet|$Dest"

# Calcul de la taille du mail
nbb=`echo -e "$Tmp" | wc -lc | awk '{print $1+$2}'`

# Envoi sur le serveur de mail
(echo "open 129.104.25.2 80";
sleep 1;
echo "POST /cgi-bin/cgi-mail/get-mail.sh HTTP/1.1";
echo "Host: $Host";
echo "Connection: close";
echo "Content-Length: $nbb";
echo "Content-Type: application/octet-stream";
echo;
echo -e "$Tmp";
sleep 1;
echo "exit") | telnet > /dev/null 2>&1
}
#-------------------------------------------------------------------------------
#------------------------------------ Main -------------------------------------
#-------------------------------------------------------------------------------

# Lecture des variables d'entree 
# $1 fichier d'entree (bck-rsync-xxx.ini)
# $2 (en Option) nom d'une machine specifique a sauvegarder
VarMachine=""
FileConf=""
FileConf="$1"
VarMachine="$2"

## Lecture dans le fichier de config des machines et creation d'un index
# ($IndexMachines) des lignes de debut de section ("NomMachine=xxxx") 
ConfigMachines=""; IndexMachines=""; Err=""
StartMachine=0; LstModules=""
LectFichierConf

if [ -n "$Err" ]; then EnvoiMail; exit 1; fi

## Tant que l'index des machines n'est pas vide on le parcourt
while [ -n "$IndexMachines" ]; do
  Deb=${IndexMachines%%-*}; tmp=${IndexMachines#*-}; Fin=${tmp%%-*}; IndexMachines="$tmp"
  if [ -z ${tmp#*-} ]; then IndexMachines=""; fi
  
  # Initialisations et lecture des parametres de la machine courante lu dans (IndexMachines)
  StartMachine=0
  OkPourBck=1
  LectureSection "$Deb" "$Fin"
  
  if [ -z "$Err" ]; then VerifConfMachine; fi
  if [ -z "$Err" ] && [ $OkPourBck -eq 1 ]; then TestBckEnCours; fi
  if [ -z "$Err" ] && [ $OkPourBck -eq 1 ]; then TestRsyncEtWol; fi
  if [ -z "$Err" ] && [ $OkPourBck -eq 1 ]; then LectConfDist; fi
  if [ -z "$Err" ] && [ $OkPourBck -eq 1 ]; then VerifQuota; fi
  if [ -z "$Err" ] && [ $OkPourBck -eq 1 ]; then BckMachine; fi
  if [ -z "$Err" ] && [ $StartMachine -eq 1 ]; then ArretDistant; fi 
  if [ -z "$Err" ] && [ $OkPourBck -ge 1 ]; then EnvoiMail; fi
  if [ -n "$Err" ]; then EnvoiMail; fi
  
  # Initialisation de la variable Err pour la machine suivante
  Err=""
done

# if (ping -c 1 192.168.0.10>nul) then    #Ping de la machine
# memo rsync -avn --delete --modify-window=1 --iconv=. --chmod=u+rwx --fake-super --exclude-from=excludes-phillis.txt  phillis::Bureau Bureau/ > liste.txt

