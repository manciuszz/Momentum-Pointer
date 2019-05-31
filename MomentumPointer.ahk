#NoEnv
#SingleInstance Force
#Persistent
ListLines, Off
Critical 1000000000000000
SetFormat, Floatfast, 0.11
SetFormat, IntegerFast, d

if (true) {
	AutoStart := new Glider()
}

class Glider {
	; static _ := Glider := new Glider()
	
	__Init() {
		this.appName := "Inertial Pointer"
		this.iniFile := "config.ini"
		this.version := "2.0"
		this.skipStartupDialog := true ; Should be false in production..
	
		this.speedThreshold := 35
		this.timeThreshold := 1055
		this.timeDial := 1007500
		this.distance := 0.665
		this.rate := -0.71575335
		
		DllCall("QueryPerformanceFrequency", "Int64*", cFr)
		this.cFf := Round(this.rate * 1000000 / cFr, 3)
		this.cFr := cFr
		
		this._setup()
	}
	
	_initSettings() {
		IniRead, resetDefaults, % this.iniFile, OSsettings, resetDefaults
		if (!FileExist(this.iniFile) || resetDefaults == "ERROR")   {
			MsgBox, 67, % "Welcome to " this.appName " v" this.version,
			(LTrim,
				It is highly recommended to use the default Windows settings for your pointing device.
				Proceed changing to defaults at launch?
				(Revert anytime at 'Start > Mouse > Pointer Options > Motion').
			)
			IfMsgBox Yes
				IniWrite, 1, % this.iniFile, OSsettings, resetDefaults
			IfMsgBox No
				IniWrite, 0, % this.iniFile, OSsettings, resetDefaults
			IfMsgBox Cancel
				ExitApp
		}
		IniRead, resetDefaults, % this.iniFile, OSsettings, resetDefaults
		this.resetDefaults := resetDefaults
	}
	
	_initOSPointerSettings() {
		;Restore to default any OS pointer settings and confirm OS pointer settings values.
		SPI_GETMOUSESPEED = 0x70
		SPI_SETMOUSESPEED = 0x71
		SPI_GETMOUSE = 0x0003
		SPI_SETMOUSE = 0x0004
		MouseSpeed := "", lpParams := ""
	
		;Set mouse speed to default 10 and get value.
		if (this.resetDefaults)
			DllCall("SystemParametersInfo", UInt, SPI_SETMOUSESPEED, UInt, 0, Ptr, 10, UInt, 0)
		
		DllCall("SystemParametersInfo", UInt, SPI_GETMOUSESPEED, UInt, 0, UIntP, MouseSpeed, UInt, 0)
		
		; Set mouse acceleration to off and get values.
		VarSetCapacity(vValue, 12, 0)
		NumPut(0, lpParams, 0, "UInt") 
		NumPut(0, lpParams, 4, "UInt")
		NumPut(0, lpParams, 8, "UInt")
		
		if (this.resetDefaults)
			DllCall("SystemParametersInfo", UInt, SPI_SETMOUSE, UInt, 0, UInt, &vValue, UInt, 1)
		
		DllCall("SystemParametersInfo", UInt, SPI_GETMOUSE, UInt, 0, UInt, &vValue, UInt, 0)
		acThr1 := NumGet(vValue, 0, "UInt")
		acThr2 := NumGet(vValue, 4, "UInt")
		acOn := NumGet(vValue, 8, "UInt") ;"Enhance pointer precision" setting
		VarSetCapacity(vValue, 0) ; Release memory
		
		if (this.resetDefaults)
			resetText := "`t--> OS settings modified! <--"
		else
			resetText := "`t--> OS settings unchanged. <--"

		IniRead, st, % this.iniFile, GlideParameters, speedThreshold
		if !(this.skipStartupDialog) {
			MsgBox, 3, % this.appName " " this.version, % "Speed Glide Threshold: " st "`n`nWindows Mouse Parameters`nSpeed: " . MouseSpeed . "`nAcceleration EnhPPr: " acOn "`nThr1: " acThr1 "`nThr2: " acThr2 "`n`n" resetText "`n`nRetain " this.appName " launch options?", 7
			IfMsgBox No	
			{
				IniDelete, % this.iniFile, OSsettings, resetDefaults
				this._setup()
			}
			IfMsgBox Cancel
				ExitApp
		} else {
			Glider.Utility.DllSleep(850)
		}
	}
	
	_initVariables() {
		this.TimePeriod := 1
		
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
	
	_velocityMonitor() {	
		; Velocity Loop - pointer movement monitor.
		Loop {
			Sleep, -1
			Glider.Utility.DllSleep(19)
			
			i := mod(A_Index, 3)
			if (!Glider.Utility.OnMouseMovement()) {
				if (this.Array2 + this.Array1 + this.Array0 < this.speedThreshold) { ; Compare filtered average speed to Glide Activation Threshold.
					this["Array"i] := 0 ; Update speed readings.
					Continue ; Below speed threshold, resume velocity monitoring.
				}
				Break ; Pointer has stopped moving. Exit velocity monitor loop and glide.
			}
			
			; Calculate: x/y axis pointer velocity vx/vy, pointer speed. Store speed and velocity components for each data point in moving average window.
			Glider.Utility.GetMousePos2D(x1, y1)
			this.x1 := x1, this.y1 := y1
			
			this.cT1 := Glider.Utility.GetTickCount()
			this["ArrayX"i] := this.cFr * (this.x1 - this.x0) / (this.cT1 - this.cT0)
			this["ArrayY"i] := this.cFr * (this.y1 - this.y0) / (this.cT1 - this.cT0)
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
		
		; if pointer will travel below 200 pixels within approx. 1s
		this.v := Sqrt(this.vx**2 + this.vy**2)
		if ((1 - Exp(this.timeThreshold * this.rate / 1000)) * this.v < 200)
			return this._velocityMonitor()
	}
	
	_glide() {
		this.Array2 := this.Array1 := this.Array0 := 0  
		; Gliding Loop - pointer glide.
		Loop {
			Glider.Utility.DllSleep(1)
			; Calculate elapsed time from Velocity Loop exit and simulate inertial pointer displacement.
			this.cT0 := Glider.Utility.GetTickCount()
			fff := 1 - Exp((this.cT0 - this.cT1) * this.cFf / this.timeDial)
			if (Glider.Utility.OnMouseMovement() || fff > 0.978) { ; Halt on user input/thresh.
				Glider.Utility.GetMousePos2D(x0, y0)
				this.x0 := x0, this.y0 := y0
				return this._startMonitoring()
			}
			DllCall("SetCursorPos", "Int", this.x1 + this.vx * fff, "Int", this.y1 + this.vy * fff)
		}
	}
	
	_main() {
		OnExit(ObjBindMethod(this.Icon, "exitFn")) ;Register a function to be called on exit.
		OnMessage(0x111, ObjBindMethod(this.Icon, "changeOnMsg"))
		
		if !(Glider.Utility.RI_RegisterDevices()) ;RawInput register. Flag QS_RAWINPUT = 0x0400
			MsgBox, RegisterRawInputDevices failure.
			
		DllCall("Winmm\timeBeginPeriod", "UInt", this.TimePeriod) ;Provide adequate resolution for Sleep.

		Menu, Tray, Icon, % "HICON:*" this.hICon
		TrayTip, % this.appName, Enabled, 0, 0

		this._startMonitoring()
	}
	
	_startMonitoring() {
		this._velocityMonitor()
		this._glide()
	}
	
	_setup() {
		this.Icon.setup(this)
		this._initSettings()
		this._initOSPointerSettings()
		this._initVariables()
		this._main()
	}
	
	class Icon {	
		setup(parentInstance) {
			this.parent := parentInstance
			
			_iconData = 0000010001001010000001002000810200001600000089504e470d0a1a0a0000000d49484452000000100000001008060000001ff3ff61000000097048597300000b1300000b1301009a9c180000023349444154388d8dd05f4853711407f0efbddbfdb3ed4e7130dd76d585fdd1c5b451442f15a340582ff5d45b504f3ed440422432881e427a280b25224744afa3049f82c010828494a1861581e0b4e9a8f6cfdddddd7b7f77bf1e82186b5c3d705e0edff3e170184a29ea6be8e6c8158e18af98aafa73f2f98376c0c4dfae01a0001800fe7f79a6117896984e5577cb9164f235646fdb72b8bb2b12bf10455bec329a15db38306b6c297af634823d07b0b0bc7aaca555bac40b5cd3e5a6805a5145629ab8188bc129b9f166eec38c5de09dfb0674a2398ac512048788c1f3e7a0d628ae3e4c14f60d504aed6a5545b15040c0df8193278e63fbd76feecef0f5f793f7c6b036376b0dd408950d9d40a96a50550da1de2338dcdb87d497ef51c92d0df3a2c31a30296175c380a6692084a0582a61a03f0c7f6710f38bab13026f3fb3d705122104ba6180520a9d1064b67710e892e1f67a917cf731610d50130621d0340d92e482e470229d4e63676b733728cbf1d60edfa025c0711c5c2e17ec2c0bd3acc1e76b8720f05015c53d323a3a55512a1b7bfc80229fcf81b20cba8341783c1ef082887ca1881713e3b7e2f11bd64f9c5f58bc9ddecafcd8cce6afe5ca4a5674883874b007a58a8a4f2b5fef36e6ff036c36769ce7b84ea7c0bf4cad7d4b28650591817e844247912b2be2d2db99687ddede08300c033b67c3d3e42c40e9f4a970df98a745822cfbe112789de5c4b4e5050c001bc3022c03d8d88da595cff73399ec7a500e4c3d7af25820c458afcfff015876e73759199f9a0000000049454e44ae426082
			this.hICon := Glider.Utility.Hex2Icon(_iconData)
			_iconData = 0000010001001010000001002000a70200001600000089504e470d0a1a0a0000000d49484452000000100000001008060000001ff3ff61000000097048597300000b1300000b1301009a9c180000025949444154388d75d25d4853611cc7f1ef993bdbcee6668a96db4437937c814a1114236c45174a17194a17451004d5ad7553187823bddc4620641408dd0c52a2842ea482228444b3f28d42d406e994f6d2ceced9dc3c5d38edb4d973f73ccffff7795e85f1c646f4ed61abef8298da18145465ede2c4c45efe6d66a014b001ab40c8905540435df5b52aaf8789af3325f7dcce4fba2907d001f40383c055a03007486f1aa2bed6a354547a189bfa72f85ddb890ec00e7401778036a001380338730025ae5852e934a7dbdbb1e6db1979fd7e384fb29c037a800a40c894ae03b11c20994a48914814b364e194ef1875a934e1e4463f50a90b2f014f809fc66c40d334a3a22ac48241ea3792949944ecaaba1d1480efc06de01590c8d9c1664a73a77fcb98e7e6f1cccce24824fede8f288681bbc03320029003084925cf343d8d6b7212aba280a68120103599795b54b4a7e8567700886ed76703f6d21f015be1d8181659de19942d16166aaa59f17a199e5dbaaf0fe8efc00e74d5cccf222acacea06ab3f1c16e27a06dc63ce5e5370b8a8b5fec0638804ea047d285e3361be1e626165783c8aa9a7fdcef7f907d6443267c16e865eba9b6569624422d2d189a9bc06a23148e3075bef3c66e800fb84ee69368a0c52529b5ec2878bce87405cd050eaaf657128d2b7cfc3cd7fb3fc09be96b022c5b15e5ca81d595eef16f0b03724ca6fed0416a6bebf815932df4f5f8b28118a0002a300ff4017e20ea1f191d08ac04595b5fc3ed76e27695250da265590fe45d76b95420044c018f809719944b5663e4b9d1244a46b1ccb5afe4e9c9a1a123dae89b901ef8030acdd4325779f2940000000049454e44ae426082
			this.hIConOff := Glider.Utility.Hex2Icon(_iconData)
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
			VarSetCapacity(Glider.Utility._POINTER, 0) ;Free memory.
			Menu, Tray, Icon, % "HICON:*" this.hIConOff
			TrayTip, % this.parent.appName, Terminating, 0, 0
			Glider.Utility.DllSleep(2000)
		}
	}
	
	class Utility {	
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
	
		GetTickCount() {
			DllCall("QueryPerformanceCounter", "Int64*", tickCount)
			return tickCount
		}
		
		DllSleep(timeMS) {
			return DllCall("Sleep", "UInt", timeMS)
		}
	
		Hex2Icon(iconDataHex) {
			VarSetCapacity(IconData, (nSize := StrLen(iconDataHex) // 2))
			Loop %nSize%
			NumPut("0x" . SubStr(iconDataHex, 2 * A_Index - 1, 2), IconData, A_Index - 1, "Char")
			hIConf := DllCall("CreateIconFromResourceEx", UInt, &IconData + 22, UInt, NumGet(IconData, 14), Int, 1, UInt, 0x30000, Int, 16, Int, 16, UInt, 0)
			VarSetCapacity(IconData, 0) ; Added freeing up of memory.
			return hIConf
		}

		RI_RegisterDevices(Page := 1, Usage := 2, Flags := 0x0100, HGUI := "") {
			Flags &= 0x3731 ; valid flags
			if Flags Is Not Integer
				return false
			if (Flags & 0x01) ; for RIDEV_REMOVE you must call RI_UnRegisterDevices()
				return false
			StructSize := 8 + A_PtrSize ; size of a RAWINPUTDEVICE structure
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
			VarSetCapacity(RID, StructSize, 0) ; RAWINPUTDEVICE structure
			NumPut(Page, RID, 0, "UShort")
			NumPut(Usage, RID, 2, "UShort")
			NumPut(Flags, RID, 4, "UInt")
			NumPut(HGUI, RID, 8, "Ptr")
			return DllCall("RegisterRawInputDevices", "Ptr", &RID, "UInt", 1, "UInt", StructSize, "UInt")
		}
	}
}