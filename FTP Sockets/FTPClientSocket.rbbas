#tag Class
Protected Class FTPClientSocket
Inherits FTPSocket
	#tag Event
		Sub Connected()
		  FTPLog("Connected to " + Me.RemoteAddress + ":" + Str(Me.Port))
		  CommandDelayTimer.Mode = Timer.ModeMultiple
		  
		End Sub
	#tag EndEvent

	#tag Event
		Sub ControlResponse(Response As FTPResponse)
		  If Response.Reply_Args.Trim <> "" Then
		    FTPLog(Response.Reply_Args.Trim)
		  Else
		    FTPLog(FTPCodeToMessage(Response.Code).Trim)
		  End If
		  Select Case LastVerb.Verb
		  Case "USER"
		    Select Case Response.Code
		    Case 230  //Logged in W/O pass
		      LoginOK = True
		      RaiseEvent Connected()
		    Case 331, 332  //Need PASS/ACCT
		      DoVerb("PASS", Me.Password)
		    End Select
		    
		  Case "PASS"
		    Select Case Response.Code
		    Case 230 //Logged in with pass
		      LoginOK = True
		      FTPLog("Ready")
		      RaiseEvent Connected()
		    Case 530  //USER not set!
		      DoVerb("USER", Me.User)
		    End Select
		  Case "RETR"
		    Select Case Response.Code
		    Case 150 //About to start data transfer
		      If OutputStream = Nil Then
		        OutputStream = BinaryStream.Open(OutputFile)
		      End If
		    Case 425, 426 //Data connection not ready
		      HandleFTPError(Response.Code)
		    Case 451, 551 //Disk read error
		      HandleFTPError(Response.Code)
		    Case 226 //Done
		      'DataSocket.Close
		      DownloadComplete(OutputFile)
		    End Select
		  Case "STOR", "APPE"
		    Select Case Response.Code
		    Case 150  //Ready
		      While Not OutputStream.EOF
		        WriteData(OutputStream.Read(512))
		      Wend
		      OutputStream.Position = 0
		      OutputStream.Close
		    Case 226  //Success
		      UploadComplete(OutputFile)
		    Case 425  //No data connection!
		      If Passive Then
		        DataSocket.Connect
		        DoVerb(LastVerb.Verb, LastVerb.Arguments)
		      Else
		        HandleFTPError(Response.Code)
		      End If
		    Case 426  //Data connection lost
		      HandleFTPError(Response.Code)
		    Else
		      HandleFTPError(Response.Code)
		    End Select
		    
		  Case "FEAT"
		    ServerFeatures = Split(Response.Reply_Args, EndOfLine.Windows)
		  Case "SYST"
		    ServerType = Response.Reply_Args
		  Case "CWD"
		    Select Case Response.Code
		    Case 250, 200 //OK
		      WorkingDirectory = LastVerb.Arguments
		    Else
		      HandleFTPError(Response.Code)
		    End Select
		    
		  Case "PWD"
		    If Response.Code = 257 Then //OK
		      WorkingDirectory = LastVerb.Arguments
		      'FTPLog("CWD is " + WorkingDirectory)
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Case "LIST"
		    Select Case Response.Code
		    Case 226 //Here comes the directory list
		      FTPLog("Directory listing...")
		    Case 425, 426  //no connection or connection lost
		      HandleFTPError(Response.Code)
		    Case 451  //Disk error
		      HandleFTPError(Response.Code)
		    Else
		      HandleFTPError(Response.Code)
		    End Select
		  Case "CDUP"
		    If Response.Code = 200 Or Response.Code = 250 Then
		      DoVerb("PWD")
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Case "PASV"
		    If Response.Code = 227 Then 'Entering Passive Mode <h1,h2,h3,h4,p1,p2>.
		      Dim p1, p2 As Integer
		      Dim h1, h2, h3, h4 As String
		      h1 = NthField(NthField(Response.Reply_Args, ",", 1), "(", 2)
		      h2 = NthField(Response.Reply_Args, ",", 2)
		      h3 = NthField(Response.Reply_Args, ",", 3)
		      h4 = NthField(Response.Reply_Args, ",", 4)
		      p1 = Val(NthField(Response.Reply_Args, ",", 5))
		      p2 = Val(NthField(Response.Reply_Args, ",", 6))
		      DataSocket.Port = p1 * 256 + p2
		      DataSocket.Address = h1 + "." + h2 + "." + h3 + "." + h4
		      FTPLog("Entering Passive Mode (" + h1 + "," + h2 + "," + h3 + "," + h4 + "," + Str(p1) + "," + Str(p2))
		      DataSocket.Connect
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Case "REST"
		    If Response.Code = 350 Then
		      OutputStream.Position = Val(LastVerb.Arguments)
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Case "PORT"
		    If Response.Code = 200 Then
		      //Active mode OK. Connect to the following port
		      DataSocket.Listen()
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Case "TYPE"
		    If Response.Code = 200 Then
		      Select Case LastVerb.Arguments
		      Case "A", "A N"
		        Me.TransferMode = ASCIIMode
		      Case "I", "L"
		        Me.TransferMode = BinaryMode
		      End Select
		    Else
		      HandleFTPError(Response.Code)
		    End If
		    
		  Case "MKD"
		    If Response.Code = 257 Then //OK
		      FTPLog("Directory created successfully.")
		      DoVerb("LIST")
		    Else
		      HandleFTPError(Response.Code)
		    End If
		    
		  Case "RMD"
		    If Response.Code = 250 Then
		      FTPLog("Directory deleted successfully.")
		      DoVerb("LIST")
		    Else
		      HandleFTPError(Response.Code)
		    End If
		    
		  Case "DELE"
		    If Response.Code = 250 Then
		      FTPLog("File deleted successfully.")
		      DoVerb("LIST")
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Case "RNFR"
		    If Response.Code = 350 Then
		      DoVerb("RNTO", RNT)
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Case "RNTO"
		    If Response.Code = 250 Then
		      DoVerb("RNTO", RNT)
		      FTPLog(RNF + " renamed to " + RNT + " successfully.")
		      RNT = ""
		      RNF = ""
		    Else
		      HandleFTPError(Response.Code)
		    End If
		  Else
		    If Response.Code = 220 Then  //Server now ready
		      FTPLog(Response.Reply_Args)
		      DoVerb("USER", Me.User)
		    Else
		      //Sync error!
		    End If
		  End Select
		  
		  'LastVerb.Verb = ""
		  'LastVerb.Arguments = ""
		  
		End Sub
	#tag EndEvent

	#tag Event
		Sub ControlVerb(Verb As FTPVerb)
		  #pragma Unused Verb
		  //Clients do not accept Verbs
		  Return
		End Sub
	#tag EndEvent

	#tag Event
		Sub TransferComplete(UserAborted As Boolean)
		  If Not UserAborted Then
		    RaiseEvent UploadComplete(OutputFile)
		  End If
		End Sub
	#tag EndEvent

	#tag Event
		Sub TransferStarting()
		  FTPLog("Data connection opened.")
		End Sub
	#tag EndEvent


	#tag Method, Flags = &h0
		Sub DoVerb(Verb As String, Params As String = "")
		  LastVerb.Verb = Verb.Trim
		  LastVerb.Arguments = Params.Trim
		  FTPLog(Verb + " " + Params)
		  Select Case Verb
		  Case "ABOR"
		    'Abort
		    Write("ABOR " + Params + CRLF)
		  Case "ACCT"
		    'Account.
		    Write("ACCT " + Params + CRLF)
		  Case "ADAT"
		    'Authentication/Security Data.
		    Write("ADAT " + Params + CRLF)
		  Case "ALLO"
		    'Allocate.
		    Write("ALLO " + Params + CRLF)
		  Case "APPE"
		    'Append.
		    Write("APPE " + Params + CRLF)
		  Case "AUTH"
		    'Authentication/Security Mechanism.
		    Write("AUTH " + Params + CRLF)
		  Case "CCC"
		    'Clear Command Channel.
		    Write("CCC " + Params + CRLF)
		  Case "CDUP"
		    'Change to parent directory.
		    Write("CDUP " + Params + CRLF)
		  Case "CONF"
		    'Confidentiality Protected Command.
		    Write("CONF " + Params + CRLF)
		  Case "CWD"
		    'Change working directory.
		    Write("CWD " + Params + CRLF)
		  Case "DELE"
		    'Delete.
		    Write("DELE " + Params + CRLF)
		  Case "ENC"
		    'Privacy Protected Command.
		    Write("ENC " + Params + CRLF)
		  Case "EPRT"
		    'Extended Data port.
		    Write("EPRT " + Params + CRLF)
		  Case "EPSV"
		    'Extended Passive.
		    Write("EPSV " + Params + CRLF)
		  Case "FEAT"
		    'Feature.
		    Write("FEAT " + Params + CRLF)
		  Case "HELP"
		    'Help.
		    Write("HELP " + Params + CRLF)
		  Case "LANG"
		    'Language negotiation.
		    Write("LANG " + Params + CRLF)
		  Case "LIST"
		    'List.
		    Write("LIST " + Params + CRLF)
		  Case "LPRT"
		    'Long data port.
		    Write("LPRT " + Params + CRLF)
		  Case "LPSV"
		    'Long passive.
		    Write("LPSV " + Params + CRLF)
		  Case "MDTM"
		    'File modification time.
		    Write("MDTM " + Params + CRLF)
		  Case "MIC"
		    'Integrity Protected Command.
		    Write("MIC " + Params + CRLF)
		  Case "MKD"
		    'Make directory.
		    Write("MKD " + Params + CRLF)
		  Case "MLSD"
		    Write("MLSD " + Params + CRLF)
		    
		  Case "MLST"
		    Write("MLST " + Params + CRLF)
		    
		  Case "MODE"
		    'Transfer mode.
		    Write("MODE " + Params + CRLF)
		  Case "NLST"
		    'Name list.
		    Write("NLST " + Params + CRLF)
		  Case "NOOP"
		    'No operation.
		    Write("NOOP " + Params + CRLF)
		  Case "OPTS"
		    'Options.
		    Write("OPTS " + Params + CRLF)
		  Case "PASS"
		    'Password.
		    Write("PASS " + Params + CRLF)
		  Case "PASV"
		    'Passive mode.
		    Write("PASV " + Params + CRLF)
		  Case "PBSZ"
		    'Protection Buffer Size.
		    Write("PBSZ " + Params + CRLF)
		  Case "PORT"
		    'Data port.
		    Dim p1, p2 As Integer
		    Dim h1, h2, h3, h4 As String
		    h1 = NthField(NthField(Params, ",", 1), "(", 2)
		    h2 = NthField(Params, ",", 2)
		    h3 = NthField(Params, ",", 3)
		    h4 = NthField(Params, ",", 4)
		    p1 = Val(NthField(Params, ",", 5))
		    p2 = Val(NthField(Params, ",", 6))
		    DataSocket.Port = p1 * 256 + p2
		    DataSocket.Address = h1 + "." + h2 + "." + h3 + "." + h4
		    params = h1 + "," + h2 + "," + h3 + "," + h4 + "," + Str(p1) + "," + Str(p2)
		    Write("PORT " + Params + CRLF)
		  Case "PROT"
		    'Data Channel Protection Level.
		    Write("PROT " + Params + CRLF)
		  Case "PWD"
		    'Print working directory.
		    Write("PWD " + Params + CRLF)
		  Case "QUIT"
		    'Logout.
		    Write("QUIT " + Params + CRLF)
		  Case "REIN"
		    'Reinitialize.
		    Write("REIN " + Params + CRLF)
		  Case "REST"
		    'Restart of interrupted transfer.
		    Write("REST " + Params + CRLF)
		  Case "RETR"
		    'Retrieve.
		    Write("RETR " + Params + CRLF)
		  Case "RMD"
		    'Remove directory.
		    Write("RMD " + Params + CRLF)
		  Case "RNFR"
		    'Rename from.
		    Write("RNFR " + Params + CRLF)
		  Case "RNTO"
		    'Rename to.
		    Write("RNTO " + Params + CRLF)
		  Case "SITE"
		    'Site parameters.
		    Write("SITE " + Params + CRLF)
		  Case "SIZE"
		    'File size.
		    Write("SIZE " + Params + CRLF)
		  Case "SMNT"
		    'Structure mount.
		    Write("SMNT " + Params + CRLF)
		  Case "STAT"
		    'Status.
		    Write("STAT " + Params + CRLF)
		  Case "STOR"
		    'Store.
		    Write("STOR " + Params + CRLF)
		  Case "STOU"
		    'Store unique.
		    Write("STOU " + Params + CRLF)
		  Case "STRU"
		    'File structure.
		    Write("STRU " + Params + CRLF)
		  Case "SYST"
		    'System.
		    Write("SYST " + Params + CRLF)
		  Case "TYPE"
		    'Representation type.
		    Write("TYPE " + Params + CRLF)
		  Case "USER"
		    'User name.
		    Write("USER " + Params + CRLF)
		    HandShakeStep = 1
		  Case "XCUP"
		    'Change to the parent of the current working directory.
		    Write("XCUP " + Params + CRLF)
		  Case "XMKD"
		    'Make a directory.
		    Write("XMKD " + Params + CRLF)
		  Case "XPWD"
		    'Print the current working directory.
		    Write("XPWD " + Params + CRLF)
		  Case "XRCP"
		    Write("XRCP " + Params + CRLF)
		    
		  Case "XRMD"
		    'Remove the directory.
		    Write("XRMD " + Params + CRLF)
		  Case "XRSQ"
		    Write("XRSQ " + Params + CRLF)
		    
		  Case "XSEM"
		    'Send, Mail if cannot.
		    Write("XSEM " + Params + CRLF)
		  Case "XSEN"
		    'Send to terminal.
		    Write("XSEN " + Params + CRLF)
		  Else
		    'Unknown Verb
		    LastVerb.Verb = ""
		    LastVerb.Arguments = ""
		    HandleFTPError(500)
		  End Select
		  
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Get(RemoteFileName As String, SaveTo As FolderItem)
		  OutputFile = SaveTo
		  DoVerb("RETR", PathEncode(RemoteFileName, WorkingDirectory))
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h1
		Protected Sub HandShake()
		  If HandShakeStep = 1 Then
		    If Password.Trim <> "" Then
		      DoVerb("PASS", Me.Password)
		    End If
		    HandShakeStep = 2
		    Return
		  ElseIf HandShakeStep = 2 Then
		    DoVerb("SYST")
		    HandShakeStep = 3
		    Return
		  ElseIf HandShakeStep = 3 Then
		    DoVerb("FEAT")
		    HandShakeStep = 4
		    Return
		  ElseIf HandShakeStep = 4 Then
		    If ServerHasFeature("UTF8") Then
		      DoVerb("OPTS", "UTF8 ON")
		    End If
		    HandShakeStep = 5
		    Return
		  ElseIf HandShakeStep = 5 Then
		    DoVerb("PWD")
		    HandShakeStep = 6
		    Return
		  ElseIf HandShakeStep = 6 Then
		    RaiseEvent Connected()
		  End If
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Mode() As Integer
		  Return TransferMode
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Mode(Assigns Mode As Integer)
		  Me.TransferMode = Mode
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Put(RemoteFileName As String, LocalFile As FolderItem)
		  If ServerHasFeature("PASV") And Me.Passive Then
		    DoVerb("PASV")
		  End If
		  If TransferMode = BinaryMode Then
		    DoVerb("TYPE", "I")
		  End If
		  OutputFile = LocalFile
		  DoVerb("STOR", WorkingDirectory + "/" + RemoteFileName)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub QueueCommand(Command As String)
		  PendingCommands.Append(Command.Trim)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ReceiveReply(ReplyNumber As Integer, ReplyMessage As String)
		  FTPLog(ReplyMessage)
		  Select Case ReplyNumber
		  Case 110
		    //Restart marker reply
		  Case 120
		    'Service ready in nnn minutes.
		    
		  Case 125
		    'Data connection already open; transfer starting.
		    
		  Case 150
		    'File status okay; about to open data connection.
		    DataSocket.Connect
		  Case 200
		    'Command okay.
		  Case 202
		    'Command not implemented, superfluous at this site.
		  Case 211
		    'System status, or system help reply.
		    'Break
		  Case 212
		    'Directory status.
		    
		  Case 213
		    'File status.
		    
		  Case 214
		    'Help message.
		    
		  Case 215
		    'NAME system type.
		    Me.ServerType = ReplyMessage
		  Case 220
		    'Service ready for new user.
		    
		  Case 221
		    'Service closing control connection.
		    
		  Case 225
		    'Data connection open; no transfer in progress.
		    
		  Case 226
		    'Closing data connection.
		    DataSocket.Close
		  Case 227
		    'Entering Passive Mode <h1,h2,h3,h4,p1,p2>.
		    Dim p1, p2 As Integer
		    Dim h1, h2, h3, h4 As String
		    h1 = NthField(NthField(ReplyMessage, ",", 1), "(", 2)
		    h2 = NthField(ReplyMessage, ",", 2)
		    h3 = NthField(ReplyMessage, ",", 3)
		    h4 = NthField(ReplyMessage, ",", 4)
		    p1 = Val(NthField(ReplyMessage, ",", 5))
		    p2 = Val(NthField(ReplyMessage, ",", 6))
		    DataSocket.Port = p1 * 256 + p2
		    DataSocket.Address = h1 + "." + h2 + "." + h3 + "." + h4
		    ReplyMessage = ("Entering Passive Mode (" + h1 + "," + h2 + "," + h3 + "," + h4 + "," + Str(p1) + "," + Str(p2))
		  Case 228
		    'Entering Long Passive Mode.
		    
		  Case 229
		    'Extended Passive Mode Entered.
		    
		  Case 230
		    'User logged in, proceed.
		    loginOK = True
		  Case 250
		    'Requested file action okay, completed.
		    
		  Case 257
		    '"PATHNAME" created.
		    FTPLog("Current directory is " + ReplyMessage)
		    WorkingDirectory = ReplyMessage
		  Case 331
		    'User name okay, need password.
		    DoVerb("PASS", Me.Password)
		  Case 332
		    'Need account for login.
		    DoVerb("PASS", Me.Password)
		  Case 350
		    'Requested file action pending further information.
		    
		  Case 421
		    'Service not available, closing control connection.
		    
		  Case 425
		    'Can't open data connection.
		    
		  Case 426
		    'Connection closed; transfer aborted.
		    
		  Case 450
		    'Requested file action not taken.
		    
		  Case 451
		    'Requested action aborted. Local error in processing.
		    
		  Case 452
		    'Requested action not taken.
		    
		  Case 500
		    'Syntax error, command unrecognized.
		    
		  Case 501
		    'Syntax error in parameters or arguments.
		    
		  Case 502
		    'Command not implemented.
		    
		  Case 503
		    'Bad sequence of commands.
		    
		  Case 504
		    'Command not implemented for that parameter.
		    
		  Case 521
		    'Supported address families are <af1, .., afn>
		    
		  Case 522
		    'Protocol not supported.
		    
		  Case 530
		    'Not logged in.
		    
		  Case 532
		    'Need account for storing files.
		    
		  Case 550
		    'Requested action not taken.
		    
		  Case 551
		    'Requested action aborted. Page type unknown.
		    
		  Case 552
		    'Requested file action aborted.
		    
		  Case 553
		    'Requested action not taken.
		    
		  Case 554
		    'Requested action not taken: invalid REST parameter.
		    
		  Case 555
		    'Requested action not taken: type or stru mismatch.
		    
		  Else
		    'Unknown
		  End Select
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h1
		Protected Function ServerHasFeature(FeatureName As String) As Boolean
		  For Each feature As String In ServerFeatures
		    If feature = FeatureName Then
		      Return True
		    End If
		  Next
		  '
		  '
		  '
		  '
		  '
		  'Return ServerFeatures.IndexOf(FeatureName) <> -1
		End Function
	#tag EndMethod


	#tag Hook, Flags = &h0
		Event Connected()
	#tag EndHook

	#tag Hook, Flags = &h0
		Event DownloadComplete(File As FolderItem)
	#tag EndHook

	#tag Hook, Flags = &h0
		Event UploadComplete(File As FolderItem)
	#tag EndHook


	#tag ComputedProperty, Flags = &h21
		#tag Getter
			Get
			  If mCommandDelayTimer = Nil Then
			    mCommandDelayTimer = New Timer
			    mCommandDelayTimer.Period = 250
			    'AddHandler mCommandDelayTimer.Action, AddressOf CommandDelayHandler
			  End If
			  return mCommandDelayTimer
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mCommandDelayTimer = value
			End Set
		#tag EndSetter
		Private CommandDelayTimer As Timer
	#tag EndComputedProperty

	#tag Property, Flags = &h21
		Private HandShakeStep As Integer
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected LoginOK As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCommandDelayTimer As Timer
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected OutputFile As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h0
		Password As String
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected PendingCommands() As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private RNF As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private RNT As String
	#tag EndProperty

	#tag Property, Flags = &h0
		User As String
	#tag EndProperty


	#tag ViewBehavior
		#tag ViewProperty
			Name="Address"
			Visible=true
			Group="Behavior"
			Type="String"
			InheritedFrom="TCPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Anonymous"
			Group="Behavior"
			InitialValue="False"
			Type="Boolean"
			InheritedFrom="FTPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="DataAddress"
			Group="Behavior"
			Type="String"
			InheritedFrom="FTPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="DataIsConnected"
			Group="Behavior"
			Type="Boolean"
			InheritedFrom="FTPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="DataLastErrorCode"
			Group="Behavior"
			Type="Integer"
			InheritedFrom="FTPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="DataPort"
			Group="Behavior"
			Type="Integer"
			InheritedFrom="FTPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
			InheritedFrom="Object"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			InheritedFrom="Object"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InheritedFrom="Object"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Passive"
			Group="Behavior"
			InitialValue="True"
			Type="Boolean"
			InheritedFrom="FTPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Password"
			Visible=true
			Group="Behavior"
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Port"
			Visible=true
			Group="Behavior"
			InitialValue="21"
			Type="Integer"
			InheritedFrom="FTPSocket"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InheritedFrom="Object"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			InheritedFrom="Object"
		#tag EndViewProperty
		#tag ViewProperty
			Name="User"
			Visible=true
			Group="Behavior"
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
