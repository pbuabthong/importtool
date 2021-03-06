// Licence: Lesser GNU Public License 2.1 (LGPL)
#pragma rtGlobals=3		// Use modern global access method.


static structure SCALA_image
	variable type
	string channelname
	string parameter
	string filename
	string direction
	string displayname
	variable r_min
	variable r_max
	variable p_min
	variable p_max
	variable resolution
	variable specnpoints
	variable specstart
	variable specend
	variable specinc
	variable specacqtime
	variable specdelay
	string specfeedback
	string unit
endstructure


static Structure SCALA_header
	variable format
	variable version
	string system
	string dates
	string user
	string comment
	string name
	string vgapc
	variable xsize // in nm
	variable ysize // in nm
	variable xpixel
	variable ypixel
	variable xinc // in nm
	variable yinc // in nm
	variable scanangle
	variable xoff  // in nm
	variable yoff  // in nm
	string method
	string dualmode
	variable delay1
	variable delay2
	variable gapv1
	variable gapv2
	variable feedset1
	variable feedset2
	variable loopgain1
	variable loopgain2
	variable xres
	variable yres
	variable measgapv
	variable meascursetp
	variable meascur
	variable scanspeed
	variable xdrift
	variable ydrift
	string scanmode
	string scandirect
	variable topTpP
	variable xgridval
	variable ygridval
	variable xpoints
	variable ylines
	variable zspeed
	variable zogain
	string zzero
	variable zigain
	variable AFMexists
	variable amplitude
	variable deltafsign
	string oscav
	variable oscfreq
	variable calFN
	variable calFL
	variable itotal
	struct SCALA_image images[100] // how many are actually supported?
	variable imagecount
endstructure


function SCALA_check_file(file)
	variable file
	fsetpos file, 0
	string line
	variable i=0
	variable found =0
	for(i = 0; i < 20; i+=1)
		FReadLine file, line
		if(strlen(line) == 0)
			fsetpos file, 0
			return -1
		endif
		line = mycleanupstr(line)
		if(strsearch(line,"Omicron SPM Control.",0)!=-1)
			found +=1
		elseif(strsearch(line,"Parameter file for SPM data.",0)!=-1)
			found +=1
		elseif(strsearch(line,"Format",0)==0)
			found +=1
		elseif(strsearch(line,"Version",0)==0)
			found +=1
		elseif(strsearch(line,"System",0)==0 && strsearch(line,"SCALA",0)!=-1)
			found +=1
		endif
	endfor
	fsetpos file, 0
	if(found !=5)
		return -1
	endif
	return 1
end


function SCALA_load_data_info(importloader)
	struct importloader &importloader
	importloader.name = "Omicron SCALA"
	importloader.filestr = "*.par"
	importloader.category = "SPM"
end


function SCALA_load_data([optfile])
	variable optfile
	optfile = paramIsDefault(optfile) ? -1 : optfile
	struct importloader importloader
	SCALA_load_data_info(importloader)
	if(loaderstart(importloader, optfile=optfile)!=0)
		return -1
	endif
	string header = importloader.header
	variable file = importloader.file

	struct SCALA_header fileheader
	//read the header file
	SCALA_read_header_file(file, header,fileheader)
	Debugprintf2("Found #"+num2str(fileheader.imagecount)+" images!",0)
	// now read the image files
	SCALA_read_image_files(file, header,fileheader)
	//read channels --> seem to be signed 2byte int (word)
	//data is in separate files
	
	// Topographic Channels:
	// height and current
	// *.tf* --> forward
	// *.tb* --> backward
	
	// Spectroscopic Channels:
	// *.sf* --> forward
	// *.sb* --> backward
	
	// Counter data
	// *.tlf*
	
	importloader.success = 1
	loaderend(importloader)
end


static function SCALA_read_image_files(file, header,fileheader)
	variable file
	string header
	struct SCALA_header &fileheader
	Fstatus file
	string filepath=S_path
	variable i=0,fileread
	string tmps, units
	for(i=0;i<fileheader.imagecount;i+=1)
		tmps = fileheader.images[i].channelname+"_"+fileheader.images[i].direction
		units = fileheader.images[i].unit
		switch(fileheader.images[i].type)
			case 0:
				// Topography channels (. tfn, . tbn) are stored line by line, beginning with lower left corner.
				tmps="Topo_"+tmps
				Make /O/R/N=(fileheader.xpixel,fileheader.ypixel)  $tmps /wave=image
				break
			case 1:
				// Spectroscopy channels (. sfn, . sbn) are stored as a sequence of frames. 
				// Each of these is a line by line image assigned to one value of the independent spectroscopy parameter.
				tmps="Spec_"+tmps
				Make /O/R/N=(fileheader.xpoints,fileheader.ylines,fileheader.images[i].specnpoints)  $tmps /wave=image
				SetScale/I z,fileheader.images[i].specstart,fileheader.images[i].specend,  units, image
				break
			default:
				return -1
				break		
		endswitch

		SetScale/I  x,0,fileheader.xsize, "nm", image
		SetScale/I  y,0,fileheader.ysize, "nm", image
		SetScale d,0,0,units image

		note image, header
		note image, "Fileinfo: "+filepath+fileheader.images[i].filename
		note image, "Channel name: "+fileheader.images[i].channelname
		note image, "Direction: "+fileheader.images[i].direction
		note image, "Name: "+fileheader.images[i].displayname
		note image, "Unit: "+fileheader.images[i].unit
		note image, "Resolution: "+num2str(fileheader.images[i].resolution)
		note image, "Min Raw Value: "+num2str(fileheader.images[i].r_min)
		note image, "Max Raw Value: "+num2str(fileheader.images[i].r_max)
		note image, "Min Real Value: "+num2str(fileheader.images[i].p_min)
		note image, "Max Real Value: "+num2str(fileheader.images[i].p_max)
		Open/R/Z=2 fileread as filepath+fileheader.images[i].filename
		Debugprintf2("... exporting: "+filepath+fileheader.images[i].filename,0)
		Fbinread/B=2/F=2 fileread, image
		Duplicate/FREE image, imagetemp


		//  flip image and 
		// Conversion to Physical Values
		variable scaling = (fileheader.images[i].p_max-fileheader.images[i].p_min)/(fileheader.images[i].r_max-fileheader.images[i].r_min)
		switch(fileheader.images[i].type)
			case 0: /// Topography channels (. tfn, . tbn) are stored line by line, beginning with lower left corner.
				image[][]=imagetemp[p][DimSize(image, 1)-q-1] // we have to mirror the wave to get the original picture
				image[][]=fileheader.images[i].p_min+(image[p][q]-fileheader.images[i].r_min)*scaling
				break
			case 1:
				image[][][]=imagetemp[p][DimSize(image, 1)-q-1][r]
				image[][][]=fileheader.images[i].p_min+(image[p][q][r]-fileheader.images[i].r_min)*scaling
				break
		endswitch
		close fileread
	endfor
end


static function /S SCALA_getparam(str)
	string str
	string ret1="", ret2="", ret3=""
	if(strsearch(str,";",0)!=-1)
		if(strsearch(str,":",0)!=-1)
			ret1=stripstrfirstlastspaces(str[0,strsearch(str,":",0)-1])
			ret2=stripstrfirstlastspaces(str[strsearch(str,":",0)+1,strsearch(str,";",0)-1])
		endif
		ret3=stripstrfirstlastspaces(str[strsearch(str,";",0)+1,inf])
	else
		if(strsearch(str,":",0)!=-1)
			ret1=stripstrfirstlastspaces(str[0,strsearch(str,":",0)-1])
			ret2=stripstrfirstlastspaces(str[strsearch(str,":",0)+1,inf])
		endif
	endif
	return ret1+"#"+ret2+"#"+ret3
end


static function SCALA_read_header_file(file, header, fileheader)
	variable file
	string header
	struct SCALA_header &fileheader
	fileheader.imagecount=0
	Fstatus file
	string tmps=""
	do
		FReadLine file, tmps
		tmps = mycleanupstr(tmps)
		tmps=SCALA_getparam(tmps)
		strswitch(StringFromList(0, tmps, "#"))
			case "Format":
				fileheader.format=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Format: "+num2str(fileheader.format),1)
				break
			case "Version":
				fileheader.version=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Version: "+num2str(fileheader.version),1)
				break
			case "System":
				fileheader.system=StringFromList(1, tmps, "#")
				Debugprintf2("System: "+fileheader.system,1)
				break
		// User Information.
			case "Date":
				fileheader.dates=StringFromList(1, tmps, "#")
				Debugprintf2("Date: "+fileheader.dates,1)
				break
			case "User":
				fileheader.user=StringFromList(1, tmps, "#")
				Debugprintf2("User: "+fileheader.user,1)
				break
			case "Comment":
				fileheader.comment=StringFromList(1, tmps, "#")	
				Debugprintf2("Comment: "+fileheader.comment,1)
				break
		// Scanner Description.
			case "Name":
				fileheader.name=StringFromList(1, tmps, "#")	
				Debugprintf2("Name: "+fileheader.name,1)
				break
			case "VGAP Contact":
				fileheader.vgapc=StringFromList(1, tmps, "#")	
				Debugprintf2("VGAP Contact: "+fileheader.vgapc,1)
				break
		// Scanner Area Description.
			case "Field X Size in nm":
				fileheader.xsize=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Field X Size in nm: "+num2str(fileheader.xsize),1)
				break
			case "Field Y Size in nm":
				fileheader.ysize=str2num(StringFromList(1, tmps, "#"))			
				Debugprintf2("Field Y Size in nm: "+num2str(fileheader.ysize),1)
				break
			case "Image Size in X":
				fileheader.xpixel=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Image Size in X : "+num2str(fileheader.xpixel),1)
				break
			case "Image Size in Y":
				fileheader.ypixel=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Image Size in Y: "+num2str(fileheader.ypixel),1)
				break
			case "Increment X":
				fileheader.xinc=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Increment X: "+num2str(fileheader.xinc),1)
				break
			case "Increment Y":
				fileheader.yinc=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Increment Y: "+num2str(fileheader.yinc),1)
				break
			case "Scan Angle":
				fileheader.scanangle=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Scan Angle: "+num2str(fileheader.scanangle),1)
				break
			case "X Offset":
				fileheader.xoff=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("X Offset: "+num2str(fileheader.xoff),1)
				break
			case "Y Offset":
				fileheader.yoff=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Y Offset: "+num2str(fileheader.yoff),1)
				break
		//Measurement parameters.
			case "SPM Method":
				fileheader.method=StringFromList(1, tmps, "#")
				Debugprintf2("SPM Method: "+fileheader.method,1)
				break
			case "Dual mode":
				fileheader.dualmode=StringFromList(1, tmps, "#")
				Debugprintf2("Dual mode: "+fileheader.dualmode,1)
				break
			case "Delay":
				fileheader.delay1=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Delay 1: "+num2str(fileheader.delay1),1)
				if(cmpstr(fileheader.dualmode,"On")==0)
					FReadLine file, tmps ; tmps = mycleanupstr(tmps)
					fileheader.delay2=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
					Debugprintf2("Delay 2: "+num2str(fileheader.delay2),1)
				endif
				break
			case "Gap Voltage":
				fileheader.gapv1=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Gap Voltage 1: "+num2str(fileheader.gapv1),1)
				if(cmpstr(fileheader.dualmode,"On")==0)
					FReadLine file, tmps ; tmps = mycleanupstr(tmps)
					fileheader.gapv2=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
					Debugprintf2("Gap Voltage 2: "+num2str(fileheader.gapv2),1)
				endif
				break
			case "Feedback Set":
				fileheader.feedset1=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Feedback Set 1: "+num2str(fileheader.feedset1),1)
				if(cmpstr(fileheader.dualmode,"On")==0)
					FReadLine file, tmps ; tmps = mycleanupstr(tmps)
					fileheader.feedset2=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
					Debugprintf2("Feedback Set 2: "+num2str(fileheader.feedset2),1)
				endif
				break
			case "Loop Gain":
				fileheader.loopgain1=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Loop Gain 1: "+num2str(fileheader.loopgain1),1)
				if(cmpstr(fileheader.dualmode,"On")==0)
					FReadLine file, tmps ; tmps = mycleanupstr(tmps)
					fileheader.loopgain2=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
					Debugprintf2("Loop Gain 2: "+num2str(fileheader.loopgain2),1)	
				endif
				break
			case "X Resolution":
				fileheader.xres=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("X Resolution: "+num2str(fileheader.xres),1)
				break
			case "Y Resolution":
				fileheader.yres=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Y Resolution: "+num2str(fileheader.yres),1)
				break
			case "Measured Gap Voltage":
				fileheader.measgapv=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Measured Gap Voltage: "+num2str(fileheader.measgapv),1)
				break
			case "Measured Current Setpoint":
				fileheader.meascursetp=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Measured Current Setpoint: "+num2str(fileheader.meascursetp),1)
				break
			case "Measured Current":
				fileheader.meascur=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Measured Current: "+num2str(fileheader.meascur),1)
				break
			case "Scan Speed":
				fileheader.scanspeed=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Scan Speed: "+num2str(fileheader.scanspeed),1)
				break
			case "X Drift":
				fileheader.xdrift=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("X Drift: "+num2str(fileheader.xdrift),1)
				break
			case "Y Drift":
				fileheader.ydrift=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Y Drift: "+num2str(fileheader.ydrift),1)
				break
			case "Scan Mode":
				fileheader.scanmode=StringFromList(1, tmps, "#")
				Debugprintf2("Scan Mode: "+fileheader.scanmode,1)
				break
			case "Scan Direction":
				fileheader.scandirect=StringFromList(1, tmps, "#")
				Debugprintf2("Scan Direction: "+fileheader.scandirect,1)
				break
			case "Topography Time per Point":
				fileheader.topTpP=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Topography Time per Point: "+num2str(fileheader.topTpP),1)
				break
			case "Spectroscopy Grid Value in X":
				fileheader.xgridval=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Spectroscopy Grid Value in X: "+num2str(fileheader.xgridval),1)
				break
			case "Spectroscopy Grid Value in Y":
				fileheader.ygridval=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Spectroscopy Grid Value in Y: "+num2str(fileheader.ygridval),1)
				break
			case "Spectroscopy Points in X":
				fileheader.xpoints=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Spectroscopy Points in X: "+num2str(fileheader.xpoints),1)
				break
			case "Spectroscopy Lines in Y":
				fileheader.ylines=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Spectroscopy Lines in Y: "+num2str(fileheader.ylines),1)
				break
		//Z Control Parameters.
			case "Z Speed":
				fileheader.zspeed=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Z Speed: "+num2str(fileheader.zspeed),1)
				break
			case "Z Output Gain":
				fileheader.zogain=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Z Output Gain: "+num2str(fileheader.zogain),1)
				break
			case "Automatic Z zero":
				fileheader.zzero=StringFromList(1, tmps, "#")
				Debugprintf2("Automatic Z zero: "+fileheader.zzero,1)
				break
			case "Z Input Gain":
				fileheader.zigain=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Z Input Gain: "+num2str(fileheader.zigain),1)
				break
		//AFM Description.
			case "AFM exists":
				fileheader.AFMexists=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("AFM exists: "+num2str(fileheader.AFMexists),1)
				break
			case "Amplitude":
				fileheader.amplitude=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Amplitude: "+num2str(fileheader.amplitude),1)
				break
			case "Delta f sign":
				fileheader.deltafsign=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Delta f sign: "+num2str(fileheader.deltafsign),1)
				break
			case "Oscillator available?":
				fileheader.oscav=StringFromList(1, tmps, "#")
				Debugprintf2("Oscillator available?: "+fileheader.oscav,1)
				break
			case "Oscillator frequency":
				fileheader.oscfreq=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Oscillator frequency: "+num2str(fileheader.oscfreq),1)
				break
			case "Calibration FN":
				fileheader.calFN=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Calibration FN: "+num2str(fileheader.calFN),1)
				break
			case "Calibration FL":
				fileheader.calFL=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("Calibration FL: "+num2str(fileheader.calFL),1)
				break
			case "I Total":
				fileheader.itotal=str2num(StringFromList(1, tmps, "#"))
				Debugprintf2("I Total: "+num2str(fileheader.itotal),1)
				break
			//Universal Counter Board Settings UCB
			case "UCB-Sync":
				break
			case "UCB-SyncSource":
				break
			case "UCB-SyncMode":
				break
			case "UCB_Counter":
				break
			case "UCB CounterMode":
				break
			case "UCB CounterIntTime":
				break
			case "UCB CounterSyncCycles":
				break
			// Spectroscopy Extra Settings.
			case "V Parameter":
				FReadLine file, tmps ; tmps = mycleanupstr(tmps) // ramp speed
				FReadLine file, tmps ; tmps = mycleanupstr(tmps) // T1
				FReadLine file, tmps ; tmps = mycleanupstr(tmps) // T2
				FReadLine file, tmps ; tmps = mycleanupstr(tmps) // T3
				FReadLine file, tmps ; tmps = mycleanupstr(tmps) // T4
				break
			case "Topographic Channel":
				Debugprintf2("Topographic Channel: "+num2str(fileheader.imagecount)+"		#########",1)
				fileheader.imagecount+=1
				fileheader.images[fileheader.imagecount-1].type = 0
				fileheader.images[fileheader.imagecount-1].channelname=StringFromList(1, tmps, "#")
				Debugprintf2("Channel name: "+fileheader.images[fileheader.imagecount-1].channelname,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1]. direction=stripstrfirstlastspaces(tmps)
				Debugprintf2("Direction: "+fileheader.images[fileheader.imagecount-1]. direction,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].r_min=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Min raw val: "+num2str(fileheader.images[fileheader.imagecount-1].r_min),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].r_max=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Max raw val: "+num2str(fileheader.images[fileheader.imagecount-1].r_max),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].p_min=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Min real val: "+num2str(fileheader.images[fileheader.imagecount-1].p_min),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].p_max=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Max real val: "+num2str(fileheader.images[fileheader.imagecount-1].p_max),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].resolution=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Resolution: "+num2str(fileheader.images[fileheader.imagecount-1].resolution),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].unit=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Unit: "+fileheader.images[fileheader.imagecount-1].unit,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].filename=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Filename: "+fileheader.images[fileheader.imagecount-1].filename,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].displayname=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Displayname: "+fileheader.images[fileheader.imagecount-1].displayname,1)
				Debugprintf2("Topographic Channel: "+num2str(fileheader.imagecount)+"end	#########",1)
			break
		case "Spectroscopy Channel":
				Debugprintf2("Spectroscopy Channel : "+num2str(fileheader.imagecount)+"		#########",1)
				fileheader.imagecount+=1
				fileheader.images[fileheader.imagecount-1].type = 1
				fileheader.images[fileheader.imagecount-1].channelname=StringFromList(1, tmps, "#")
				Debugprintf2("Channel name: "+fileheader.images[fileheader.imagecount-1].channelname,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].parameter=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Parameter: "+fileheader.images[fileheader.imagecount-1].parameter,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1]. direction=stripstrfirstlastspaces(tmps)
				Debugprintf2("Direction: "+fileheader.images[fileheader.imagecount-1]. direction,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].r_min=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Min raw val: "+num2str(fileheader.images[fileheader.imagecount-1].r_min),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].r_max=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Max raw val: "+num2str(fileheader.images[fileheader.imagecount-1].r_max),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].p_min=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Min real val: "+num2str(fileheader.images[fileheader.imagecount-1].p_min),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].p_max=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Max real val: "+num2str(fileheader.images[fileheader.imagecount-1].p_max),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].resolution=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Resolution: "+num2str(fileheader.images[fileheader.imagecount-1].resolution),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].unit=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Unit: "+fileheader.images[fileheader.imagecount-1].unit,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].specnpoints=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Points: "+num2str(fileheader.images[fileheader.imagecount-1].specnpoints),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].specstart=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Start: "+num2str(fileheader.images[fileheader.imagecount-1].specstart),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].specend=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("End: "+num2str(fileheader.images[fileheader.imagecount-1].specend),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].specinc=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Increment: "+num2str(fileheader.images[fileheader.imagecount-1].specinc),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].specacqtime=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Acquisition time: "+num2str(fileheader.images[fileheader.imagecount-1].specacqtime),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].specdelay=str2num(ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],""))
				Debugprintf2("Delay time: "+num2str(fileheader.images[fileheader.imagecount-1].specdelay),1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].specfeedback=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Feedback: "+fileheader.images[fileheader.imagecount-1].specfeedback,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].filename=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Filename: "+fileheader.images[fileheader.imagecount-1].filename,1)
				FReadLine file, tmps ; tmps = mycleanupstr(tmps)
				fileheader.images[fileheader.imagecount-1].displayname=ReplaceString(" ",tmps[0,strsearch(tmps,";",0)-1],"")
				Debugprintf2("Displayname: "+fileheader.images[fileheader.imagecount-1].displayname,1)
				Debugprintf2("Topographic Channel: "+num2str(fileheader.imagecount)+"end	#########",1)
			break
		default:
			//nothing found
			break
		endswitch
		fstatus file
	while(V_logEOF>V_filePOS)

end
