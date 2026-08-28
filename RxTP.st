
//**********************************Declaration****************************************
PROGRAM CAN1_ENGINE_Int
VAR
	ReadResult: lib500_types.IO_ERRORTYPE;			//temporary CALL result
	WriteResult: lib500_types.IO_ERRORTYPE;			//temporary CALL result
	
	CANDataBuff: tCanMsg;
	TP_RxBuff: tCanTPBuff;			//buffer to store Transfer Protocol data
	PGNReceived: DWORD;				//PGN from received message
	DAReceived: BYTE;				//DA from received message
	BAM_Running: BOOL;				//BAM was started
	BAM_Finished: BOOL;				//BAM was finished OK
	RTS_Running: BOOL;
	RTS_Finished: BOOL;
	ActPacketNr: BYTE;				//Actual Packet Nr.
	i: BYTE;
	Pass: BYTE;
	
END_VAR
//**************************************************************************************

//***********************************CODE***********************************************

	ReadResult := lib500.IO_CAN_ReadMsg(handle:= GVL_CAN.gCan1.hReceiver[GVL_CAN.gCAN1_ENGINERecID], buffer:= ADR(CANDataBuff));		//read data
	IF (ReadResult = lib500_types.IO_ERRORTYPE.IO_E_OK) OR (ReadResult = lib500_types.IO_ERRORTYPE.IO_E_CAN_OVERFLOW) THEN
	
	//decide what message it was
	PGNReceived := (SHR(CANDataBuff.CobId,8) AND 16#0000FF00);
	DAReceived := DWORD_TO_BYTE(SHR(CANDataBuff.CobId,8) AND 16#000000FF);
	CASE PGNReceived OF
		GVL_CAN.cCAN_TP_CM:			//TP Connection 
			IF (CANDataBuff.Data[0] = GVL_CAN.cBamId) AND (DAReceived = GVL_CAN.cGlobalAdr) THEN		//It is TP_CM_BAM 
				BAM_Running :=  TRUE;			//BAM was started now
				BAM_Finished := FALSE;
				Pass :=0;
				//decode transfer data
				TP_RxBuff.Length := MEM.PackBytesToWord(byHighByte:= CANDataBuff.Data[2], byLowByte:= CANDataBuff.Data[1]);
				TP_RxBuff.Packets := CANDataBuff.Data[3];
				TP_RxBuff.PGN := MEM.PackBytesToDword(byHHByte:= 0, byHLByte:= 0, byLHByte:= CANDataBuff.Data[6], byLLByte:= CANDataBuff.Data[5]);
				// Relay to other CAN's
				IF ((TP_RxBuff.PGN = GVL_CAN.cCAN_DM1_PGN) OR (TP_RxBuff.PGN = GVL_CAN.cCAN_DM2_PGN)) THEN
					Can3TxMsg(iCAN:= ADR(CANDataBuff), oResult=> WriteResult); // transfer to CAN3
				END_IF
			ELSIF (CANDataBuff.Data[0] = GVL_CAN.cBamId) AND (DAReceived = GVL_CAN.cCAN1_CabDisplay1Adr) THEN 	//It is TP_CP_BAM with PDU specific DA 0x28	 
				RTS_Running :=  TRUE;			//BAM was started now
				RTS_Finished := FALSE;
				Pass :=0;
				//decode transfer data
				TP_RxBuff.Length := MEM.PackBytesToWord(byHighByte:= CANDataBuff.Data[2], byLowByte:= CANDataBuff.Data[1]);
				TP_RxBuff.Packets := CANDataBuff.Data[3];
				TP_RxBuff.PGN := MEM.PackBytesToDword(byHHByte:= 0, byHLByte:= 0, byLHByte:= CANDataBuff.Data[6], byLLByte:= CANDataBuff.Data[5]);
				// Relay to other CAN's
				IF ((TP_RxBuff.PGN = GVL_CAN.cCAN_DM1_PGN) OR (TP_RxBuff.PGN = GVL_CAN.cCAN_DM2_PGN)) THEN
					Can3TxMsg(iCAN:= ADR(CANDataBuff), oResult=> WriteResult); // transfer to CAN3
				END_IF
			END_IF
		
		GVL_CAN.cCAN_TP_DT:			//TP Data
			IF (BAM_Running = TRUE) THEN		//It is TP_DT of BAM
				ActPacketNr := CANDataBuff.Data[0];
				Pass := Pass + 1;
				//decode transfer data
				FOR i := 0 TO 6 DO
					TP_RxBuff.Data[((ActPacketNr - 1)*7) + i] := CANDataBuff.Data[i + 1];		//put right data to desired place
				END_FOR
				// Relay to other CAN's
				IF ((TP_RxBuff.PGN = GVL_CAN.cCAN_DM1_PGN) OR (TP_RxBuff.PGN = GVL_CAN.cCAN_DM2_PGN)) THEN
					Can3TxMsg(iCAN:= ADR(CANDataBuff), oResult=> WriteResult); // transfer to CAN3
				END_IF
				//Last Packet
				IF(ActPacketNr = TP_RxBuff.Packets) THEN		//it was the last packet
					BAM_Running :=  FALSE;			//BAM finished now
					BAM_Finished := TRUE;
				END_IF
			ELSIF (RTS_Running = TRUE) THEN
				ActPacketNr := CANDataBuff.Data[0];
				Pass := Pass + 1;
				//decode transfer data
				FOR i := 0 TO 6 DO
					TP_RxBuff.Data[((ActPacketNr - 1)*7) + i] := CANDataBuff.Data[i + 1];		//put right data to desired place
				END_FOR
				// Relay to other CAN's
				IF ((TP_RxBuff.PGN = GVL_CAN.cCAN_DM1_PGN) OR (TP_RxBuff.PGN = GVL_CAN.cCAN_DM2_PGN)) THEN
					Can3TxMsg(iCAN:= ADR(CANDataBuff), oResult=> WriteResult); // transfer to CAN3
				END_IF
				//Last Packet
				IF(ActPacketNr = TP_RxBuff.Packets) THEN		//it was the last packet
					RTS_Running :=  FALSE;			//BAM finished now
					RTS_Finished := TRUE;
				END_IF
			END_IF
			
	END_CASE
	
	//Decode received message
	IF 	BAM_Finished THEN		//it was BAM Message
		
		CASE TP_RxBuff.PGN OF
			GVL_CAN.cCAN_EC1_BAM_PGN:		//EC1 was received
				// SPN 545 EngineGainOfEndSpeedGov %  in EC1
				GVL.gEngineGainOfEndSpeedGov := (WORD_TO_REAL((TP_RxBuff.Data[18] * 256) + TP_RxBuff.Data[17])) / 1280;
				//SPN 533 EngineMaximumMomentaryOvrSpdPnt7 RPM  in EC1
				GVL.gEngineSpeedAtHighIdlePoint6 := (WORD_TO_REAL((TP_RxBuff.Data[16] * 256) + TP_RxBuff.Data[15])) / 8;
				//SPN 188 EngineSpeedAtIdlePoint1 RPM in EC1
	//++++docasne zakomentovano chyba je u DEUTZ			
				//GVL.gEngineSpeedAtIdlePoint1 := (WORD_TO_REAL((TP_RxBuff.Data[1] * 256) + TP_RxBuff.Data[0])) / 8;
				
				GVL.gwEC1_BAM_TimeCount := 0;		//received, reset the watchdog
				GVL_CAN.gCAN1_EC1_BAMTimeOut := FALSE;
		END_CASE
	
	BAM_Finished := FALSE;					//decode finished	
	ELSIF RTS_Finished THEN 
		RTS_Finished := FALSE;					//decode finished	
	END_IF
	
END_IF

//********************************************tCANTPBuff*******************************************************************
TYPE tCanTPBuff :
STRUCT
	Data		: ARRAY[0..1786] OF BYTE;	(* holds the 8 data bytes of the CAN frame *)
	Length		: WORD;						(* number of valid bytes in this frame *)
	Packets		: BYTE;						(* number of 7 byte packets in this frame *)
	PGN			: DWORD;					(* CAN PGN *)
END_STRUCT
END_TYPE


//********************************************tCANmessage******************************************************************************
TYPE tCanMsg :
STRUCT
	Data		: ARRAY[0..7] OF BYTE;	(* holds the 8 data bytes of the CAN frame *)
	Length		: BYTE;						(* number of valid bytes in this frame *)
	Id_Format	: BYTE;						(* ID format | 0 = standard | 1 = extended *)
	CobId		: DWORD;					(* CAN ID *)
END_STRUCT
END_TYPE
