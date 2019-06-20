; #Warn
#NoEnv
#Persistent
#SingleInstance Force
Critical 1000000000000000
SetFormat, FloatFast, 0.11
SetFormat, IntegerFast, d
ListLines, Off
; SetBatchLines, -1 ; "Determines how fast a script will run (affects CPU utilization)."

if (true) {
	if ((AttachDebugger := false) && WinExist("ahk_exe notepad++.exe")) {
		hiddenWindowState := A_DetectHiddenWindows
		DetectHiddenWindows, On
		if WinExist(A_ScriptFullPath " ahk_class AutoHotkey")
			PostMessage DllCall("RegisterWindowMessage", "str", "AHK_ATTACH_DEBUGGER")
		DetectHiddenWindows, % hiddenWindowState
	}
	AutoStart := new App()
	return
}

class App {
	; static _ := App := new App() ; Interesting fact?: This makes AHK Loop run slow for whatever reason...
	
	__Init() {		
		this.appName := "Momentum Pointer"
		this.iniFile := "config.ini"
		this.version := "2.0"
	
		this.configSectionName := "MomentumParameters"
		
		; Defaults Values
		this.speedThreshold := 35
		this.timeThreshold := 1055
		this.timeDial := 1007500
		this.distance := 0.665
		this.rate := -0.71575335
		
		getParamFromConfig := ObjBindMethod(App.Utility, "GetParamFromIni", this.iniFile, this.configSectionName)	
		this.skipStartupDialog := GetKeyState("CapsLock", "T") ? 0 : %getParamFromConfig%(App.Strings.skipStartupDialog, false)
		
		this.speedThreshold := %getParamFromConfig%(App.Strings.Params.speedThreshold, this.speedThreshold)
		this.timeThreshold := %getParamFromConfig%(App.Strings.Params.timeThreshold, this.timeThreshold)
		this.timeDial := %getParamFromConfig%(App.Strings.Params.timeDial, this.timeDial)
		this.distance := %getParamFromConfig%(App.Strings.Params.distance, this.distance)
		this.rate := %getParamFromConfig%(App.Strings.Params.rate, this.rate)

		this.getFreqCount := App.Utility.GetFrequencyCounter()
		this.rateOffset := Round(this.rate * (1000000 / this.getFreqCount), 3)
		
		this.monitorSleepTime := 25
		this.suspendedStateSleepInterval := 1000

		App.Icon.setup(this)

		if (true) { ; This is super experimental stuff at the moment...		
			this.shouldPreventTouchpadChanges := false ; True will always prevent automatic touchpad changes, otherwise it will check for "Leave touchpad on when mouse is connected" checkbox inside System Settings.
			this.reEnableTouchpadInterval := 500 ; Value <= 0 will disable the feature completely.
			this.touchpadSettings := new App.Touchpad(this)
		}
		
		if !(this.skipStartupDialog)
			this.guiInstance := new App.GUI(this)
			
		if !(this.guiInstance)
			this.setup()
	}
	
	setup() {
		this._initSettings()
		this._initOSPointerSettings()
		this._initVariables()
		this._main()
	}

	shouldRestoreCriticalState(stackTrace, isCritical := "") { ; TODO: this could use a refactor sometime..
		if (stackTrace == "typingSuspender") {
			this.madeCritical := true
		} else if (this.madeCritical && isCritical == 0 && stackTrace == "velocityMonitor") {
			this.madeCritical := false
			return true
		}
		return this.madeCritical
	}
	
	_initSettings() {
		this._osSettingsParams := { iniFile: this.iniFile, sectionName: "OSsettings", paramName: "resetDefaults", defaultParam: "ERROR" }
		
		resetDefaults := App.Utility.GetParamFromIni(this._osSettingsParams)
		if (!FileExist(this.iniFile) || resetDefaults == "ERROR") {
			MsgBox, 67, % "Welcome to " this.appName " v" this.version,
			(LTrim,
				It is highly recommended to use the default Windows settings for your pointing device.
				Proceed changing to defaults at launch?
				(Revert anytime at 'Start > Mouse > Pointer Options > Motion').
			)
			IfMsgBox Yes
			{
				this._osSettingsParams.paramToWrite := 1
				App.Utility.SetParamToIni(this._osSettingsParams)
				this.setup()
			}
			IfMsgBox No
			{
				this._osSettingsParams.paramToWrite := 0
				App.Utility.SetParamToIni(this._osSettingsParams)
				this.skipStartupDialog := 1
			}
			IfMsgBox Cancel
				ExitApp
		}
		this.resetDefaults := App.Utility.GetParamFromIni(this._osSettingsParams)
	}
	
	; Note that these settings seems to not have any effect on Precision Touchpad Q.Q
	_initOSPointerSettings() {
		;Restore to default any OS pointer settings and confirm OS pointer settings values.
		SPI_GETMOUSESPEED = 0x70
		SPI_SETMOUSESPEED = 0x71
		SPI_GETMOUSE = 0x0003
		SPI_SETMOUSE = 0x0004
		MouseSpeed := "", lpParams := ""
	
		User32Module := DllCall("GetModuleHandle", Str, "user32", "Ptr")
		SPIProc := DllCall("GetProcAddress", "Ptr", User32Module, "AStr", "SystemParametersInfoW", "Ptr")
	
		;Set mouse speed to default 10 and get value.
		if (this.resetDefaults)
			DllCall(SPIProc, UInt, SPI_SETMOUSESPEED, UInt, 0, UInt, 10, UInt, 0)
		
		DllCall(SPIProc, UInt, SPI_GETMOUSESPEED, UInt, 0, UIntP, MouseSpeed, UInt, 0)
		
		; Set mouse acceleration to off and get values.
		VarSetCapacity(vValue, 12, 0)
		NumPut(0, lpParams, 0, "UInt") 
		NumPut(0, lpParams, 4, "UInt")
		NumPut(0, lpParams, 8, "UInt")
		
		if (this.resetDefaults)
			DllCall(SPIProc, UInt, SPI_SETMOUSE, UInt, 0, UInt, &vValue, UInt, 1)
		
		DllCall(SPIProc, UInt, SPI_GETMOUSE, UInt, 0, UInt, &vValue, UInt, 0)
		acThr1 := NumGet(vValue, 0, "UInt")
		acThr2 := NumGet(vValue, 4, "UInt")
		acOn := NumGet(vValue, 8, "UInt") ;"Enhance pointer precision" setting
		VarSetCapacity(vValue, 0) ; Release memory
		
		if (this.resetDefaults)
			resetText := "`t--> OS settings modified! <--"
		else
			resetText := "`t--> OS settings unchanged. <--"

		if !(this.skipStartupDialog) {
			myDialogText := ""
			. "`n" "Speed Glide Threshold: " this.speedThreshold
			. "`n" "Windows Mouse Parameters"
			. "`n" "Speed: " MouseSpeed
			. "`n" "Acceleration EnhPPr: " acOn
			. "`n" "Thr1: " acThr1
			. "`n" "Thr2: " acThr2
			. "`n`n" resetText
			. "`n`n" "Retain " this.appName " launch options?"
			MsgBox, 3, % this.appName " " this.version, % myDialogText
			IfMsgBox No	
			{
				App.Utility.DeleteParamFromIni(this._osSettingsParams)
				this.setup()
			}
			IfMsgBox Cancel
				ExitApp
		} else {
			App.Utility.DllSleep(1000)
		}
	}
	
	_initVariables(_timePeriod := 7) {
		this.TimePeriod := _timePeriod
		
		; Counters
		this.cT0 := this.cT1 := 0 
		
		; Coordinates
		this.x1 := this.y1 := this.x0 := this.y0 := 0
		
		; Speeds
		this.fff := 0
		this.v := 0
		this.vx := this.vy := 0
		this.Array0 := this.Array1 := this.Array2 := 0 
		
		; Velocity components
		this.ArrayX0 := this.ArrayY0 := this.ArrayX1 := this.ArrayY1 := this.ArrayX2 := this.ArrayY2 := 0
	}
		
	_startMonitoring() {
		velocityMonitor:		
			App.Utility.CleanMemory()
			; Velocity Loop - pointer movement monitor.
			Loop {
				if (this.shouldRestoreCriticalState("velocityMonitor", A_IsCritical)) {
					Critical 1000000000000000
				}
				
				if (this.forceExit) {
					Sleep, % this.suspendedStateSleepInterval
					continue
				}
								
				Sleep, -1
				App.Utility.DllSleep(this.monitorSleepTime)
				
				i := mod(A_Index, 3)
				if (!App.Utility.OnMouseMovement()) {
					if (this.Array2 + this.Array1 + this.Array0 < this.speedThreshold) { ; Compare filtered average speed to Glide Activation Threshold.
						this["Array"i] := 0 ; Update speed readings.
						Continue ; Below speed threshold, resume velocity monitoring.
					}
					Break ; Pointer has stopped moving. Exit velocity monitor loop and glide.
				}
				
				; Calculate: x/y axis pointer velocity vx/vy, pointer speed. Store speed and velocity components for each data point in moving average window.
				App.Utility.GetMousePos2D(x1, y1)
				this.x1 := x1, this.y1 := y1
				
				this.cT1 := App.Utility.GetTickCount()
				this["ArrayX"i] := this.getFreqCount * (this.x1 - this.x0) / (this.cT1 - this.cT0)
				this["ArrayY"i] := this.getFreqCount * (this.y1 - this.y0) / (this.cT1 - this.cT0)
				this["Array"i] := Round(Sqrt(this["ArrayX"i]**2 + this["ArrayY"i]**2))
				
				this.x0 := this.x1, this.y0 := this.y1
				this.cT0 := this.cT1
			}
			
			; Get highest speed and equivalent velocity readings within moving average window.
			if (this.Array0 > this.Array1 && this.Array0 > this.Array2) {
				this.vx := Round(this.distance * this.ArrayX0)
				this.vy := Round(this.distance * this.ArrayY0)
			} else if (this.Array1 > this.Array2) {
				this.vx := Round(this.distance * this.ArrayX1)
				this.vy := Round(this.distance * this.ArrayY1)
			} else {
				this.vx := Round(this.distance * this.ArrayX2)
				this.vy := Round(this.distance * this.ArrayY2)
			}
			
			this.v := Sqrt(this.vx**2 + this.vy**2)
			; if pointer will travel below 200 pixels within approx. 1s
			if ((1 - Exp(this.timeThreshold * this.rate / 1000)) * this.v < 200)
				Goto, velocityMonitor
			Goto, Glide
		Return
		
		Glide:
			this.Array2 := this.Array1 := this.Array0 := 0  
			; Gliding Loop - pointer glide.
			Loop {
				if (this.forceExit) {
					Sleep, % this.suspendedStateSleepInterval
					continue
				}
				App.Utility.DllSleep(1)
				; Calculate elapsed time from Velocity Loop exit and simulate inertial pointer displacement.
				this.cT0 := App.Utility.GetTickCount()
				fff := (1 - Exp((this.cT0 - this.cT1) * this.rateOffset / this.timeDial))
				if (App.Utility.OnMouseMovement() || fff > 0.978) { ; Halt on user input/thresh.
					App.Utility.GetMousePos2D(x0, y0)
					this.x0 := x0, this.y0 := y0
					Goto, velocityMonitor
				}
				
				x := this.x1 + this.vx * fff
				y := this.y1 + this.vy * fff
				DllCall("SetCursorPos", "Int", x, "Int", y)
			}
		Return
	}
	
	_main() {
		OnExit(ObjBindMethod(this.Icon, "exitFn")) ; Register a function to be called on exit.
		OnMessage((WM_COMMAND := 0x111), ObjBindMethod(this.Icon, "changeOnMsg"))
		
		if !(App.Utility.RI_RegisterDevices()) ; RawInput register. Flag QS_RAWINPUT = 0x0400
			MsgBox, RegisterRawInputDevices failure.
		
		if (!A_IsSuspended) {			
			Menu, Tray, Icon, % "HICON:*" this.hICon
			TrayTip, % this.appName, Enabled, 0, 0
		}			

		DllCall("Winmm\timeBeginPeriod", "UInt", this.TimePeriod) ; Provide adequate resolution for Sleep.
		this._startMonitoring()
	}
		
	class Icon {	
		setup(parentInstance) {
			this.parent := parentInstance
			
			_iconData = 0000010001001010000001002000810200001600000089504e470d0a1a0a0000000d49484452000000100000001008060000001ff3ff61000000097048597300000b1300000b1301009a9c180000023349444154388d8dd05f4853711407f0efbddbfdb3ed4e7130dd76d585fdd1c5b451442f15a340582ff5d45b504f3ed440422432881e427a280b25224744afa3049f82c010828494a1861581e0b4e9a8f6cfdddddd7b7f77bf1e82186b5c3d705e0edff3e170184a29ea6be8e6c8158e18af98aafa73f2f98376c0c4dfae01a0001800fe7f79a6117896984e5577cb9164f235646fdb72b8bb2b12bf10455bec329a15db38306b6c297af634823d07b0b0bc7aaca555bac40b5cd3e5a6805a5145629ab8188bc129b9f166eec38c5de09dfb0674a2398ac512048788c1f3e7a0d628ae3e4c14f60d504aed6a5545b15040c0df8193278e63fbd76feecef0f5f793f7c6b036376b0dd408950d9d40a96a50550da1de2338dcdb87d497ef51c92d0df3a2c31a30296175c380a6692084a0582a61a03f0c7f6710f38bab13026f3fb3d705122104ba6180520a9d1064b67710e892e1f67a917cf731610d50130621d0340d92e482e470229d4e63676b733728cbf1d60edfa025c0711c5c2e17ec2c0bd3acc1e76b8720f05015c53d323a3a55512a1b7bfc80229fcf81b20cba8341783c1ef082887ca1881713e3b7e2f11bd64f9c5f58bc9ddecafcd8cce6afe5ca4a5674883874b007a58a8a4f2b5fef36e6ff036c36769ce7b84ea7c0bf4cad7d4b28650591817e844247912b2be2d2db99687ddede08300c033b67c3d3e42c40e9f4a970df98a745822cfbe112789de5c4b4e5050c001bc3022c03d8d88da595cff73399ec7a500e4c3d7af25820c458afcfff015876e73759199f9a0000000049454e44ae426082
			this.hICon := this.Hex2Icon(_iconData)
			_iconData = 0000010001001010000001002000a70200001600000089504e470d0a1a0a0000000d49484452000000100000001008060000001ff3ff61000000097048597300000b1300000b1301009a9c180000025949444154388d75d25d4853611cc7f1ef993bdbcee6668a96db4437937c814a1114236c45174a17194a17451004d5ad7553187823bddc4620641408dd0c52a2842ea482228444b3f28d42d406e994f6d2ceced9dc3c5d38edb4d973f73ccffff7795e85f1c646f4ed61abef8298da18145465ede2c4c45efe6d66a014b001ab40c8905540435df5b52aaf8789af3325f7dcce4fba2907d001f40383c055a03007486f1aa2bed6a354547a189bfa72f85ddb890ec00e7401778036a001380338730025ae5852e934a7dbdbb1e6db1979fd7e384fb29c037a800a40c894ae03b11c20994a48914814b364e194ef1875a934e1e4463f50a90b2f014f809fc66c40d334a3a22ac48241ea3792949944ecaaba1d1480efc06de01590c8d9c1664a73a77fcb98e7e6f1cccce24824fede8f288681bbc03320029003084925cf343d8d6b7212aba280a68120103599795b54b4a7e8567700886ed76703f6d21f015be1d8181659de19942d16166aaa59f17a199e5dbaaf0fe8efc00e74d5cccf222acacea06ab3f1c16e27a06dc63ce5e5370b8a8b5fec0638804ea047d285e3361be1e626165783c8aa9a7fdcef7f907d6443267c16e865eba9b6569624422d2d189a9bc06a23148e3075bef3c66e800fb84ee69368a0c52529b5ec2878bce87405cd050eaaf657128d2b7cfc3cd7fb3fc09be96b022c5b15e5ca81d595eef16f0b03724ca6fed0416a6bebf815932df4f5f8b28118a0002a300ff4017e20ea1f191d08ac04595b5fc3ed76e27695250da265590fe45d76b95420044c018f809719944b5663e4b9d1244a46b1ccb5afe4e9c9a1a123dae89b901ef8030acdd4325779f2940000000049454e44ae426082
			this.hIConOff := this.Hex2Icon(_iconData)
			Menu, Tray, Icon, % "HICON:*" this.hIConOff
			Menu, Tray, Tip, % this.parent.appName
			
			this.parent.hICon := this.hICon
			this.parent.hIConOff := this.hIConOff
		}
		
		changeOnMsg(wParam) {
			this.iconToggle := ""
			if (wParam = 65305) {
				this.iconToggle := A_IsSuspended
			} else if (wParam = 65306) {
				this.iconToggle := A_IsPaused
			}
				
			if (this.iconToggle != "") {
				this[this.iconToggle ? "resume" : "pause"]()
			}
		}
		
		pause() {
			TrayTip, % this.parent.appName, Paused., 0, 0
			Menu, Tray, Icon, % "HICON:*" this.hIConOff
			Menu, Tray, Icon,,, 1
			this.parent._initVariables()
		}
		
		resume() {
			TrayTip, % this.parent.appName, Resumed!, 0, 0
			Menu, Tray, Icon, % "HICON:*" this.hICon
		}
		
		exitFn(ExitReason, ExitCode) {
			DllCall("Winmm\timeEndPeriod", UInt, this.parent.TimePeriod) ; Should be called to restore system to normal.
			VarSetCapacity(App.Utility._POINTER, 0) ;Free memory.
			Menu, Tray, Icon, % "HICON:*" this.hIConOff
			TrayTip, % this.parent.appName, Terminating, 0, 0
			App.Utility.DllSleep(2000)
		}
		
		Hex2Icon(iconDataHex) {
			VarSetCapacity(IconData, (nSize := StrLen(iconDataHex) // 2))
			Loop %nSize%
				NumPut("0x" . SubStr(iconDataHex, 2 * A_Index - 1, 2), IconData, A_Index - 1, "Char")
			hIConf := DllCall("CreateIconFromResourceEx", UInt, &IconData + 22, UInt, NumGet(IconData, 14), Int, 1, UInt, 0x30000, Int, 16, Int, 16, UInt, 0)
			VarSetCapacity(IconData, 0) ; Release 'IconData' from memory.
			return hIConf
		}
	}
	
	class Utility {	
		RunSelfAsAdministrator() {
			if not A_IsAdmin {
				Run *RunAs "%A_ScriptFullPath%"
				ExitApp
			}
			return A_IsAdmin
		}
	
		GetMousePos2D(byRef x0, byRef y0) {
			static _POINTER := false
			if (!_POINTER) {
				VarSetCapacity(POINTER, 12, 0)
				_POINTER := POINTER
			}
			DllCall("GetCursorPos", "Ptr", &_POINTER)
			x0 := NumGet(_POINTER, 0, "Int")
			y0 := NumGet(_POINTER, 4, "Int")
		}
	
		OnMouseMovement() {
			return (DllCall("GetQueueStatus", "UInt", 0x0400) >> 16) & 0xFFFF
		}
	
		GetFrequencyCounter() {
			; getFreqCount := -1
			DllCall("QueryPerformanceFrequency", "Int64*", getFreqCount)
			return getFreqCount
		}		
		
		GetTickCount() {
			; tickCount := -1
			DllCall("QueryPerformanceCounter", "Int64*", tickCount)
			return tickCount
		}
		
		DllSleep(timeMS) {
			return DllCall("Sleep", "UInt", timeMS)
		}
		
		GetParamFromIni(args*) {
			selectedFunction := this["GetParamFromIni" args.MaxIndex()]
			return %selectedFunction%(this, args*)
		}
		
		GetParamFromIni1(params) {	
			return this.GetParamFromIni4(params.iniFile, params.sectionName, params.paramName, params.defaultParam)
		}
		
		GetParamFromIni4(iniFile, sectionName, paramName, defaultParam) {
			IniRead, foundParam, %iniFile%, %sectionName%, %paramName%
			if (foundParam == "ERROR")
				foundParam := defaultParam
			return foundParam
		}
		
		SetParamToIni(args*) {
			selectedFunction := this["SetParamToIni" args.MaxIndex()]
			return %selectedFunction%(this, args*)
		}
		
		SetParamToIni1(params) {
			return this.SetParamToIni4(params.iniFile, params.sectionName, params.paramName, params.paramToWrite)
		}
		
		SetParamToIni4(iniFile, sectionName, paramName, paramToWrite) {
			IniWrite, %paramToWrite%, %iniFile%, %sectionName%, %paramName%
			return paramToWrite
		}
		
		DeleteParamFromIni(args*) {
			selectedFunction := this["DeleteParamFromIni" args.MaxIndex()]
			return %selectedFunction%(this, args*)
		}
		
		DeleteParamFromIni1(params) {
			return this.DeleteParamFromIni3(params.iniFile, params.sectionName, params.paramName)
		}
		
		DeleteParamFromIni3(iniFile, sectionName, paramName) {
			IniDelete, % iniFile, % sectionName, % paramName
		}
		
		RI_RegisterDevices(Page := 1, Usage := 2, Flags := 0x0100, HGUI := "") {
			Flags &= 0x3731 ; valid flags
			if Flags Is Not Integer
				return false
			if (Flags & 0x01) ; for RIDEV_REMOVE you must call RI_UnRegisterDevices()
				return false
			
			; Usage has to be zero in case of RIDEV_PAGEONLY, flags must include RIDEV_PAGEONLY if Usage is zero.
			if ((Flags & 0x30) = 0x20)
				Usage := 0
			else if (Usage = 0)
				Flags |= 0x20
			; HWND needs to be zero in case of RIDEV_EXCLUDE
			if ((Flags & 0x30) = 0x10)
				HGUI := 0
			else if (HGUI = "")
				HGUI := A_ScriptHwnd
				
			StructSize := 8 + A_PtrSize ; size of a RAWINPUTDEVICE structure
			VarSetCapacity(RID, StructSize, 0) ; RAWINPUTDEVICE structure
			NumPut(Page, RID, 0, "UShort")
			NumPut(Usage, RID, 2, "UShort")
			NumPut(Flags, RID, 4, "UInt")
			NumPut(HGUI, RID, 8, "Ptr")
			return DllCall("RegisterRawInputDevices", "Ptr", &RID, "UInt", 1, "UInt", StructSize, "UInt")
		}
		
		CleanMemory(PID = ""){
			PID := ((PID = "") ? DllCall("GetCurrentProcessId") : PID)
			hWnd := DllCall("OpenProcess", "UInt", 0x001F0FFF, "Int", 0, "Int", PID)
			DllCall("SetProcessWorkingSetSize", "UInt", hWnd, "Int", -1, "Int", -1)
			DllCall("CloseHandle", "Int", hWnd)
		}
		
		StdOutStream(sCmd, Callback := "", WorkingDir := 0, ByRef ProcessID := 0) {
		   static StrGet := "StrGet"
		   tcWrk := WorkingDir=0 ? "Int" : "Str"
		   DllCall( "CreatePipe", UIntP,hPipeRead, UIntP,hPipeWrite, UInt,0, UInt,0 )
		   DllCall( "SetHandleInformation", UInt,hPipeWrite, UInt,1, UInt,1 )
		   if A_PtrSize = 8 ; x64 bit
		   {
			  VarSetCapacity( STARTUPINFO, 104, 0  )   
			  NumPut( 68,         STARTUPINFO,  0 )    
			  NumPut( 0x100,      STARTUPINFO, 60 )    
			  NumPut( hPipeWrite, STARTUPINFO, 88 )    
			  NumPut( hPipeWrite, STARTUPINFO, 96 )    
			  VarSetCapacity( PROCESS_INFORMATION, 24 )
		   } else {
			  VarSetCapacity( STARTUPINFO, 68, 0  )
			  NumPut( 68,         STARTUPINFO,  0 )
			  NumPut( 0x100,      STARTUPINFO, 44 )
			  NumPut( hPipeWrite, STARTUPINFO, 60 )
			  NumPut( hPipeWrite, STARTUPINFO, 64 )
			  VarSetCapacity( PROCESS_INFORMATION, 16 )
		   }
		   
		   if ! DllCall( "CreateProcess", UInt,0, UInt,&sCmd, UInt,0, UInt, 0, UInt,1, UInt,0x08000000, UInt,0, tcWrk, WorkingDir, UInt,&STARTUPINFO, UInt,&PROCESS_INFORMATION ) {
			  DllCall( "CloseHandle", UInt,hPipeWrite ) 
			  DllCall( "CloseHandle", UInt,hPipeRead )
			  DllCall( "SetLastError", Int,-1 )     
			  Return ""
		   }
		   
		   hProcess := NumGet( PROCESS_INFORMATION, 0 )                 
		   hThread  := NumGet( PROCESS_INFORMATION, A_PtrSize )  
		   ProcessID:= NumGet( PROCESS_INFORMATION, A_PtrSize*2 )  
		   
		   DllCall( "CloseHandle", UInt,hPipeWrite )
		   
		   AIC := ( SubStr( A_AhkVersion, 1, 3 ) = "1.0" )
		   VarSetCapacity( Buffer, 4096, 0 ), nSz := 0 
		   
		   while DllCall( "ReadFile", UInt,hPipeRead, UInt,&Buffer, UInt,4094, UIntP,nSz, Int,0 ) {
			  tOutput := ( AIC && NumPut( 0, Buffer, nSz, "Char" ) && VarSetCapacity( Buffer,-1 ) ) ? Buffer : %StrGet%( &Buffer, nSz, "CP0" )
			  IsFunc( Callback ) ? %Callback%( tOutput, A_Index ) : sOutput .= tOutput
		   }                   
		   
		   DllCall( "GetExitCodeProcess", UInt,hProcess, UIntP,ExitCode )
		   DllCall( "CloseHandle",  UInt,hProcess  )
		   DllCall( "CloseHandle",  UInt,hThread   )
		   DllCall( "CloseHandle",  UInt,hPipeRead )
		   DllCall( "SetLastError", UInt,ExitCode  )
		   VarSetCapacity(STARTUPINFO, 0)
		   VarSetCapacity(PROCESS_INFORMATION, 0)
		   
		   Return IsFunc( Callback ) ? %Callback%( "", 0 ) : sOutput
		}
		
		EvalPowershell(psScript) {
			return this.StdOutStream("powershell.exe -ExecutionPolicy Bypass -Command &{" . psScript . "}")
		}
	}
	
	class GUI {
		__New(parentInstance) {
			this.parent := parentInstance
			this.guiName := this.parent.appName . " | Parameters"
			this.paramsMenu().render()
		}
		
		render() {
			Gui, Show,, % this.guiName
		}
		
		_onClose() {
			GuiClose:
				ExitApp
			return
		}
		
		paramsMenu() {
			this.addLabels()
			this.addInputFields()
			this.addReadonlyFields()
			this.addMenuButton()
			this.fillInputFields()
			return this
		}
		
		saveButton() {
			inputFieldValues := { 
			(Join,
				speedThreshold: this.getInputValue(App.Strings.ActiveField.speedThreshold)
				timeThreshold: this.getInputValue(App.Strings.ActiveField.timeThreshold)
				timeDial: this.getInputValue(App.Strings.ActiveField.timeDial)
				distance: this.getInputValue(App.Strings.ActiveField.distance)
				rate: this.getInputValue(App.Strings.ActiveField.rate)
			)}
			
			for field, value in inputFieldValues {
				if (!RegExMatch(value, "^\-?(((\d+)?\.)?[\d]+$)")) {
					MsgBox % "Field '" . field . "' value " . value . " is invalid!"
					return
				}
			}
			
			Gui, Submit
					
			writeToConfig := ObjBindMethod(App.Utility, "SetParamToIni", this.parent.iniFile, this.parent.configSectionName)
			this.parent.speedThreshold := %writeToConfig%(App.Strings.Params.speedThreshold, inputFieldValues.speedThreshold)
			this.parent.timeThreshold := %writeToConfig%(App.Strings.Params.timeThreshold, inputFieldValues.timeThreshold)
			this.parent.timeDial := %writeToConfig%(App.Strings.Params.timeDial, inputFieldValues.timeDial)
			this.parent.distance := %writeToConfig%(App.Strings.Params.distance, inputFieldValues.distance)
			this.parent.rate := %writeToConfig%(App.Strings.Params.rate, inputFieldValues.rate)
			
			%writeToConfig%(App.Strings.skipStartupDialog, this.getInputValue(App.Strings.ActiveField.checkboxState))
			
			this.parent.setup()
		}
		
		addLabels() {
			this.addMenuOption("Lower for easier gliding (defaultPlaceholder).`t`t`tAverage speed threshold:", this.parent.speedThreshold)
			this.addMenuOption("Lower for larger deadzone (defaultPlaceholder).`t`t`tAbsolute time limit:", this.parent.timeThreshold)
			this.addMenuOption("Lower for faster gliding (defaultPlaceholder).`t`tTime dial:", this.parent.timeDial)
			this.addMenuOption("Lower for shorter gliding (defaultPlaceholder).`t`t`tGlide distance:", this.parent.distance)
			this.addMenuOption("Lower for constant acceleration (defaultPlaceholder).`tGlide rate:", this.parent.rate)
			this.addMenuOption("Disable Startup Dialog:")
		}
		
		addInputFields() {			
			this.editMenuOption("Edit", "Text", App.Strings.ActiveField.speedThreshold, "NewColumn")
			this.editMenuOption("Edit", "Text", App.Strings.ActiveField.timeThreshold)
			this.editMenuOption("Edit", "Text", App.Strings.ActiveField.timeDial)
			this.editMenuOption("Edit", "Text", App.Strings.ActiveField.distance)
			this.editMenuOption("Edit", "Text", App.Strings.ActiveField.rate)
			this.editMenuOption("Checkbox", !this.parent.skipStartupDialog ? "Checked" : "", App.Strings.ActiveField.checkboxState)
		}
		
		addReadonlyFields() {
			ReadOnlyFLAG := true
			this.editMenuOption("Edit",, App.Strings.ReadOnlyField.speedThreshold, "NewColumn", ReadOnlyFLAG)
			this.editMenuOption("Edit",, App.Strings.ReadOnlyField.timeThreshold,, ReadOnlyFLAG)
			this.editMenuOption("Edit",, App.Strings.ReadOnlyField.timeDial,, ReadOnlyFLAG)
			this.editMenuOption("Edit",, App.Strings.ReadOnlyField.distance,, ReadOnlyFLAG)
			this.editMenuOption("Edit",, App.Strings.ReadOnlyField.rate,, ReadOnlyFLAG)
		}
		
		fillInputFields() {
			this.mapInput(App.Strings.ActiveField.speedThreshold, this.parent.speedThreshold)
			this.mapInput(App.Strings.ActiveField.timeThreshold, this.parent.timeThreshold)
			this.mapInput(App.Strings.ActiveField.timeDial, this.parent.timeDial)
			this.mapInput(App.Strings.ActiveField.distance, this.parent.distance)
			this.mapInput(App.Strings.ActiveField.rate, this.parent.rate)
			
			this.mapInput(App.Strings.ReadOnlyField.speedThreshold, this.parent.speedThreshold)
			this.mapInput(App.Strings.ReadOnlyField.timeThreshold, this.parent.timeThreshold)
			this.mapInput(App.Strings.ReadOnlyField.timeDial, this.parent.timeDial)
			this.mapInput(App.Strings.ReadOnlyField.distance, this.parent.distance)
			this.mapInput(App.Strings.ReadOnlyField.rate, this.parent.rate)
		}
		
		addMenuOption(labelPattern, defaultValue := "") {
			Gui, Add, Text,, % StrReplace(labelPattern, "defaultPlaceholder", defaultValue)
		}
		
		addMenuButton() {
			global
			Gui, Add, Button, vButton1, OK
			local saveButtonFunc := this.saveButton.Bind(this)
			GuiControl +g, Button1, % saveButtonFunc
		}
		
		editMenuOption(controlType := "Edit", variableOptions := "Text", controlName := "", newColumn := "", readOnly := false) {
			global
			local controlCount := NumGet(&this.controlMap, 4 * A_PtrSize)
			if !(controlCount)
				this.controlMap := {}
			this.controlMap[controlName] := "MenuOption" . controlCount
			
			local isNewColumn := (newColumn == "NewColumn" ? "ym" : "")
			local isReadOnly := (readOnly ? "ReadOnly" : "")
			
			Gui, Add, % controlType, %variableOptions% vMenuOption%controlCount% %isNewColumn% %isReadOnly%
		}
		
		mapInput(controlID, inputValue) {
			GuiControl,, % this.controlMap[controlID], % inputValue
		}
		
		getInputValue(controlID) {
			GuiControlGet, outputVar,, % this.controlMap[controlID]
			return outputVar
		}
		
	}
	
	class Touchpad {
		; static mouhidRegPath := "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\mouhid\Enum"
		; static enumRegPath := "HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Enum\HID\"

		__New(parentInstance) { ; TODO: 'this.PrecisionTouchPad' should be a general touchpad that implements all other types of touchpads
			this.parent := parentInstance
			
			this.PrecisionTouchPad.preventTouchpadChanges := (!this.PrecisionTouchPad.getLOWMRegistryState() || parentInstance.shouldPreventTouchpadChanges) 
			if (!this.PrecisionTouchPad.preventTouchpadChanges)
				if (!App.Utility.RunSelfAsAdministrator())
					return

			if (App.Utility.EvalPowershell("echo 1")) { ; Check to see if we can actually use PowerShell...
				this.onDeviceChange()
				OnMessage((WM_DEVICECHANGE := 0x219), ObjBindMethod(this, "onDeviceChange"))
			}			
			
			if (parentInstance.reEnableTouchpadInterval > 0 && this.PrecisionTouchPad.preventTouchpadChanges)
				new this.TypingSuspender(this)
		}              
		
		_identifyMouseDevices() { ; Note: It's a little slow for my liking, but gets the job done nonetheless....
			psScript =
			(
				$PNPMice = Get-WmiObject Win32_USBControllerDevice | `% {[wmi]$_.dependent} | ?{$_.pnpclass -eq 'Mouse'}
				$PNPMice | `% { $_.Name }
			)
			myDevices := App.Utility.EvalPowershell(psScript)
			return StrSplit(myDevices, "`n").MaxIndex() - 1 > 0 ; Note -1 is due to the output always having a new line at the end...
		}
		
		; _identifyMouseDevices() { ; Note: Works on my machine, but not sure how good is this method of mouse detection when taking all machines into account, otherwise I'd prefer this..
			; mouseMap := {}
			
			; RegRead, mouseDeviceCount, % this.mouhidRegPath, Count
			; if (mouseDeviceCount > 0) {
				; Loop % mouseDeviceCount {				
					; mouseID := A_Index - 1
					; RegRead, deviceHID, % this.mouhidRegPath, % mouseID
					; deviceHID := StrSplit(deviceHID, "\").2
					; Loop, Reg, % this.enumRegPath . deviceHID, K 
					; {
						; if (A_LoopRegName) {
							; RegRead, deviceDescription, % this.enumRegPath . deviceHID . "\" . A_LoopRegName, DeviceDesc
							; mouseMap[mouseID] := deviceDescription
							; break							
						; }
					; }
				; }
			; }
			; mouseMap.length := mouseDeviceCount
			; return mouseMap.length > 1 ; In most cases, laptops has a touchpad, so the length would always be 1... meanwhile connecting a USB device should obviously increase the value.
		; }

		onDeviceChange() {						
			this.externalDevicesConnected := this._identifyMouseDevices()
					
			if (!this.PrecisionTouchPad.preventTouchpadChanges) {
				if (this.externalDevicesConnected && this.PrecisionTouchpad.getTouchpadState()) {
					this.PrecisionTouchpad.setTouchpadState("Disabled")
					OnExit(ObjBindMethod(this.PrecisionTouchpad, "setTouchpadState", "Enabled")) ; This will always be called when AHK process exits... unless it dies, then your left without your touchpad lol!
				} else if (!this.externalDevicesConnected) {
					this.PrecisionTouchpad.setTouchpadState("Enabled")
				}
			}

			this._suspender(this.externalDevicesConnected)
		}
		
		_suspender(condition) {
			if (condition && !this.parent.forceExit)
				this.parent.Icon.pause()
			else if (!condition && this.parent.forceExit)
				this.parent.Icon.resume()
			Suspend, % (condition ? "On" : "Off")
			this.parent.forceExit := condition
		}
		
		class PrecisionTouchpad { ; Seems like there's no API for working with Precision Touchpad... makes me cry a river.
			static regPath := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad"
			
			; Note that registry tweaks are READ-ONLY!... If only we could force registry tweaks take immediate effect...
			getLOWMRegistryState() {
				RegRead, leaveOnWithMouse, % this.regPath, LeaveOnWithMouse
				return leaveOnWithMouse
			}
			
			setLOWMRegistryState(state := "Disabled") { ; This tweak requires a PC restart or sign-in/out to take effect... Need a new solution!
				if (this.getLOWMRegistryState() != "") {
					stateMap := { "Enabled": 0xffffffff, "Disabled": 0 }
					RegWrite, REG_DWORD, % this.regPath, LeaveOnWithMouse, % stateMap[state]
				}				
			}
		
			getTouchpadState() {
				psScript = 
				(
					$Touchpad = Get-PnpDevice | `% { if ($_.FriendlyName -match 'TouchPad|Touch Pad') { $_ } }
					if ($Touchpad.Status -eq 'OK') { 1 } else { 0 }
				)
				return App.Utility.EvalPowershell(psScript)
			}
			
			; A much better alternative to this would be "Run, SystemSettingsAdminFlows.exe EnableTouchPad 0/1" if it worked with AHK...
			setTouchpadState(forceState := "Enabled") { ; Changes at the driver level... ~~ *somebody screams in the background* -pun intended
				if (this.preventTouchpadChanges)
					return
					
				if (!A_IsAdmin) {
					MsgBox, % "Need 'Administrator' user rights to use 'PrecisionTouchPad.setTouchpadState' method!"
					return
				}					
					
				setState := ({ "Enabled": "Enable", "Disabled": "Disable" })[forceState]
				psScript = 
				(
					$Touchpad = Get-PnpDevice | `% { if ($_.FriendlyName -match 'TouchPad|Touch Pad') { $_ } }
					$HID = $Touchpad.InstanceId
					%setState%-PnpDevice -InstanceId $HID -Confirm:$false
				)
				App.Utility.EvalPowershell(psScript)
			}
		}
		
		; class ElanTouchpad {
			; TODO: Implement this
		; }
		
		; class SynapticsTouchpad {
			; TODO: Implement this
		; }
		
		class TypingSuspender {
			
			__New(parentInstance) {
				this.touchpad := parentInstance
				
				this.reEnableTouchpadMethod := ObjBindMethod(this, "reEnableTouchpad")
				this.hHookKeybd := this.setWindowsHookEx((WH_KEYBOARD_LL := 13), RegisterCallback(this.keyboard.name, "Fast", "", &this))
				OnExit(ObjBindMethod(this, "unhookWindowsHookEx", this.hHookKeybd)) ; Register a function to be called on exit.
			}
			
			reEnableTouchpad() {
				BlockInput, MouseMoveOff
				this.touchpad.parent.shouldRestoreCriticalState("typingSuspender")
			}
			
			toggleTimer(timerFunc, state, priority := 0) {
				SetTimer, % timerFunc, % state, % priority
			}
			
			keyboard(nCode, wParam, lParam) {
				lParam := wParam
				wParam := nCode
				nCode := this
				this := Object(A_EventInfo)
				
				if (this.touchpad.externalDevicesConnected)
					return
								
				if ((wParam = 0x100) || (wParam = 0x101)) { ; WM_KEYDOWN || WM_KEYUP
					Critical Off
					BlockInput, MouseMove
					this.toggleTimer(this.reEnableTouchpadMethod, this.touchpad.parent.reEnableTouchpadInterval)
				}
				return this.callNextHookEx(nCode, wParam, lParam, this.hHookKeybd)
			}
			
			setWindowsHookEx(idHook, callbackFn) {  ; Note this might create conflicts with other AHK scripts that uses keyboard, therefore lets send a message that reloads all* AHK scripts 
			   this._reloadScripts()
			   return DllCall("SetWindowsHookEx", "int", idHook, "Uint", callbackFn, "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr") 
			}
			
			unhookWindowsHookEx(hHook) {
			   return DllCall("UnhookWindowsHookEx", "Uint", hHook)
			}
			
			callNextHookEx(nCode, wParam, lParam, hHook = 0) {
			   return DllCall("CallNextHookEx", "Uint", hHook, "int", nCode, "Uint", wParam, "Uint", lParam)
			}	
			
			_reloadScripts() {
				previousStates := { hiddenWindows: A_DetectHiddenWindows, titleMatchMode: A_TitleMatchMode }
				DetectHiddenWindows, On
				SetTitleMatchMode, 2
				WinGet, ahkExeList, List, ahk_class AutoHotkey
				Loop, % ahkExeList {
					scriptHwnd := ahkExeList%A_Index%
					if (scriptHwnd = A_ScriptHwnd) {
						continue
					}
					PostMessage, 0x111, 65303,,, % "ahk_id" . scriptHwnd
				}
				DetectHiddenWindows, % previousStates.hiddenWindows
				SetTitleMatchMode, % previousStates.titleMatchMode
			}
		}
	}
	
	class Strings {	

		static skipStartupDialog := "skipStartupDialog"
		
		class Params {
			static speedThreshold := "speedThreshold"
			static timeThreshold := "timeThreshold"
			static timeDial := "timeDial"
			static distance := "distance"
			static rate := "rate"
		}	

		class ActiveField extends App.Strings.Params {
			static _ := App.Strings.ActiveField := new App.Strings.ActiveField()
			
			static checkboxState := "checkboxState"

			__Get(vKey) {
				return "activeField" . vKey
			}
		}
		
		class ReadOnlyField extends App.Strings.Params {
			static _ := App.Strings.ReadOnlyField := new App.Strings.ReadOnlyField()
			
			__Get(vKey) {
				return "readOnlyField" . vKey
			}
		}
	}
}
