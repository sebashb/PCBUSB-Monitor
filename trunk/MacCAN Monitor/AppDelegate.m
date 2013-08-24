//
//  AppDelegate.m
//  MacCAN Monitor
//
//  Created by Uwe Vogt on 18.08.13.
//  Copyright (c) 2013 UV Software. All rights reserved.
//

#import "AppDelegate.h"
#import "CANMessage.h"
#import <mach/mach_time.h>


#define MAX_CAN_MESSAGES    1024


const struct {
    TPCANBaudrate btr0btr1;
    unsigned short value;
} gBaudrate[9] = {
    {PCAN_BAUD_1M, 1000},
    {PCAN_BAUD_500K, 500},
    {PCAN_BAUD_250K, 250},
    {PCAN_BAUD_125K, 125},
    {PCAN_BAUD_100K,100},
    {PCAN_BAUD_50K, 50},
    {PCAN_BAUD_20K, 20},
    {PCAN_BAUD_10K, 10},
    {PCAN_BAUD_5K, 5}
};


@implementation AppDelegate

@synthesize window = _window;

- (void)awakeFromNib
{
    [imageIcon setImage:[NSApp applicationIconImage]];
    
    indexInterface = 0;
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 1] copy]];
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 2] copy]];
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 3] copy]];
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 4] copy]];
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 5] copy]];
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 6] copy]];
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 7] copy]];
    [comboInterface addItemWithObjectValue:[[NSString stringWithFormat:@"PCAN-USB%i", 8] copy]];
    [comboInterface selectItemAtIndex:indexInterface];
    [comboInterface setEditable:NO];
    
    indexBaudrate = 2;  // FIXME = 3;
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[0].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[1].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[2].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[3].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[4].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[5].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[6].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[7].value] copy]];
    [comboBaudrate addItemWithObjectValue:[[NSString stringWithFormat:@"%i kBit/s", gBaudrate[8].value] copy]];
    [comboBaudrate selectItemAtIndex:indexBaudrate];
    [comboBaudrate setEditable:NO];
    
    [checkboxLog setState:NSOffState];
    
    modeTimestamp = TIME_ZERO;
    
    hDevice = PCAN_NONEBUS;
    frameCounter = 0;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    [NSApp beginSheet:connectSheet modalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    TPCANStatus result;
    
    if(hDevice != PCAN_NONEBUS)
    {
        result = CAN_Uninitialize(hDevice);
        
        NSString *string = [NSString stringWithFormat:@"PCAN-USB%li %s disconnected",indexInterface+1,(result == PCAN_ERROR_OK)? "successfully" : "not"];
        [outputStatus setStringValue:string];
        NSLog(@"%@",string);        
    }
}

- (IBAction)showConnectSheet:(id)sender
{
    [NSApp beginSheet:connectSheet modalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
}

- (IBAction)endConnectSheet:(id)sender
{
    [NSApp endSheet:connectSheet];
    [connectSheet orderOut:sender];
}


- (IBAction)connectInterface:(id)sender
{
    TPCANStatus result;
    
    indexInterface = [comboInterface indexOfSelectedItem];
    indexBaudrate = [comboBaudrate indexOfSelectedItem];
    
    if([checkboxLog state] == NSOnState)
    {
        result = CAN_SetValue(PCAN_NONEBUS, PCAN_EXT_LOG_USB, NULL, 0);
        NSLog(@"Logging %s",result? "not possible" : "enabled");
    }
    if((result = CAN_Initialize(PCAN_USBBUS1 + (TPCANHandle)indexInterface, gBaudrate[indexBaudrate].btr0btr1, 0, 0, 0)) == PCAN_ERROR_OK)
    {
        receiveTimer = [NSTimer timerWithTimeInterval:0.020 target:self selector:@selector(receiveTick:) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:receiveTimer forMode:NSDefaultRunLoopMode];
        
        NSString *string = [NSString stringWithFormat:@"Connected to PCAN-USB%li @ %i kBit/s",indexInterface+1,gBaudrate[indexBaudrate].value];
        [outputStatus setStringValue:string];
        NSLog(@"%@",string);
        
        hDevice = PCAN_USBBUS1 + (TPCANHandle)indexInterface;
    }
    else
    {
        char errorText[256] = "(unknown)";
        (void)CAN_GetErrorText(result, 0x00, errorText);
        
        NSString *string = [NSString stringWithFormat:@"Not connected - Error %04lx: %s",result,errorText];
        [outputStatus setStringValue:string];
        NSLog(@"%@",string);
        
        hDevice = PCAN_NONEBUS;
        
        NSAlert *alert = [NSAlert alertWithMessageText:@"Interface could not be connected." defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"error %04lx: %s",result,errorText];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert beginSheetModalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
    }
    [self endConnectSheet:sender];
}

- (IBAction)showInfo:(id)sender
{
    char hardware[256] = "(unknown)";
    char software[256] = "(unknown)";
    char baudrate[4+1] = "???";
    unsigned short btr0btr1 = 0x0000;
    TPCANStatus status = PCAN_ERROR_OK;
    
    status = CAN_GetValue(hDevice, PCAN_CHANNEL_VERSION, (void*)hardware, 256);
    status = CAN_GetValue(hDevice, PCAN_API_VERSION, (void*)software, 256);
    status = CAN_GetValue(hDevice, PCAN_EXT_BTR0BTR1, (void*)&btr0btr1, sizeof(btr0btr1));
    status = CAN_GetStatus(hDevice);
    
    if((status & ~PCAN_ERROR_ANYBUSERR) == PCAN_ERROR_OK)
    {
        switch(btr0btr1) {
            case PCAN_BAUD_1M: strcpy(baudrate, "1000"); break;
            case PCAN_BAUD_500K: strcpy(baudrate, "500"); break;
            case PCAN_BAUD_250K: strcpy(baudrate, "250"); break;
            case PCAN_BAUD_125K: strcpy(baudrate, "125"); break;
            case PCAN_BAUD_100K: strcpy(baudrate, "100"); break;
            case PCAN_BAUD_50K: strcpy(baudrate, "50"); break;
            case PCAN_BAUD_20K: strcpy(baudrate, "20"); break;
            case PCAN_BAUD_10K: strcpy(baudrate, "10"); break;
            case PCAN_BAUD_5K: strcpy(baudrate, "5"); break;
            default: strcpy(baudrate, "???"); break;
        }
        NSAlert *alert = [NSAlert alertWithMessageText:@"MacCAN Monitor using libPCBUSB" defaultButton:@"OK" alternateButton:nil otherButton:nil
#ifdef _SHOW_INFO_BAUDRATE
                             informativeTextWithFormat:@"Hardware:\n   %s\nSoftware:\n   %s\nBaud rate:\n   %s kBit/s (%04x)",hardware,software,baudrate,btr0btr1];
#else
    informativeTextWithFormat:@"Hardware:\n   %s\nSoftware:\n   %s",hardware,software];
#endif
        [alert beginSheetModalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
    }
    else
    {
        char errorText[256] = "(unknown)";
        (void)CAN_GetErrorText(status, 0x00, errorText);
        
        NSAlert *alert = [NSAlert alertWithMessageText:@"Information could not be read." defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"error %04lx: %s",status,errorText];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert beginSheetModalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
    }
}

- (IBAction)clearView:(id)sender
{
    clearViewRequest = YES;
}

- (IBAction)showTransmitSheet:(id)sender
{
    [NSApp beginSheet:transmitSheet modalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
}

- (IBAction)endTransmitSheet:(id)sender
{
    [textMessage setStringValue:@""];
    
    [NSApp endSheet:transmitSheet];
    [transmitSheet orderOut:sender];
}


- (IBAction)transmitMessage:(id)sender
{
    unsigned valueInput[9];
    TPCANMsg canMessage;
    TPCANStatus status;
    
    NSString *stringInput = [textMessage stringValue];
    NSArray *arrayInput = [stringInput componentsSeparatedByString:@" "];
    for(int i = 0; i < [arrayInput count] && i < 9; i++)
    {
        NSScanner *scanner = [NSScanner scannerWithString:[arrayInput objectAtIndex:i]];
        [scanner scanHexInt:&valueInput[i]];
    }
    if(![stringInput isEqualToString:@""] && [arrayInput count] > 0)
    {
        canMessage.MSGTYPE = PCAN_MESSAGE_STANDARD;
        canMessage.ID = (DWORD)valueInput[0];
        canMessage.LEN = (BYTE)0x00;
        for(int i = 1; i < [arrayInput count] && i < 9; i++)
        {
            canMessage.DATA[canMessage.LEN] = (BYTE)valueInput[i];
            canMessage.LEN++;
        }
        if((status = CAN_Write(hDevice, &canMessage)) == PCAN_ERROR_OK)
        {
	        NSMutableString *textData = [NSMutableString stringWithCapacity:(3*8)];
	        NSMutableString *textAscii = [NSMutableString stringWithCapacity:(3*8)];
	        for(UInt8 i = 0; i < canMessage.LEN; i++)
	        {
	            [textData appendFormat:@"%02x%c",canMessage.DATA[i],((i+1) < canMessage.LEN)? ' ' : 0];
	            [textAscii appendFormat:@"%c ",(canMessage.DATA[i] < 32)? '.' : canMessage.DATA[i]];
	        }
	        CANMessage *newMessage = [[CANMessage alloc] init];
	        [newMessage setNumber:[NSString stringWithFormat:@"%llu",frameCounter++]];
	        [newMessage setTimestamp:[NSString stringWithFormat:@" 0:00:00.000.000"]];
	        [newMessage setIdentifier:[NSString stringWithFormat:@"%03lx",canMessage.ID]];
	        [newMessage setType:[NSString stringWithFormat:@"trm"]];
	        [newMessage setData:textData];
	        [newMessage setAscii:textAscii];
	        [arrayController addObject:newMessage];
            
	        NSMutableString *stringOutput = [NSMutableString stringWithCapacity:(4)+(3*8)];
            [stringOutput appendFormat:@"%03lx ",canMessage.ID];
            [stringOutput appendString:textData];
            [comboMessage addItemWithObjectValue:stringOutput];
            [textMessage setStringValue:@""];
        }
        else
        {
            char errorText[256] = "(unknown)";
            (void)CAN_GetErrorText(status, 0x00, errorText);
            
            NSAlert *alert = [NSAlert alertWithMessageText:@"Message could not be sent." defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"error %04lx: %s",status,errorText];
            [alert setAlertStyle:NSCriticalAlertStyle];
            [alert beginSheetModalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
        }
    }
}

- (void)receiveTick:(NSTimer *)theTimer
{
    TPCANMsg canMessage;
    TPCANTimestamp canTimestamp;
    TPCANStatus result;
    int n = 0;
    static int r = 0;
    UInt64 timeStamp;
    UInt64 microseconds;
    static UInt64 lastStamp;
    static int firstTime = 1;
    /* [MACCAN-2] */
	long long value;
    static long long expected = 0ULL;
    
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    
    uint64_t start = mach_absolute_time();
    
    if(clearViewRequest)
    {
        //uint64_t s = mach_absolute_time();
        
        NSUInteger arrayCount = [[arrayController arrangedObjects] count];
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, arrayCount)];
        [arrayController removeObjectsAtArrangedObjectIndexes:indexSet];
        
        frameCounter = 0;
        firstTime = 1;
        r = 0;
        clearViewRequest = NO;
        
        //uint64_t d = mach_absolute_time() - s;
        //NSLog(@"clear = %lluns for %lu object(s)",((d*info.numer)/info.denom),arrayCount);
    }
    uint64_t duration = mach_absolute_time() - start;
    
    do
    {
	    if((result = CAN_Read(hDevice, &canMessage, &canTimestamp)) == PCAN_ERROR_OK)
	    {
	        NSMutableString *textType = [NSMutableString stringWithCapacity:(3)];
	        NSMutableString *textData = [NSMutableString stringWithCapacity:(3*8)];
	        NSMutableString *textAscii = [NSMutableString stringWithCapacity:(3*8)];
	        NSMutableString *textTimestamp = [NSMutableString stringWithCapacity:25];
	        switch(canMessage.MSGTYPE)
	        {
	            case PCAN_MESSAGE_STANDARD:
	                [textType setString:@"rcv"];
	                break;
	            case PCAN_MESSAGE_RTR:
	                [textType setString:@"rtr"];
	                break;
	            case PCAN_MESSAGE_EXTENDED:
	                [textType setString:@"ext"];
	                break;
	            case PCAN_MESSAGE_STATUS:
	                [textType setString:@"err"];
	                break;
	            default:
	                [textType setString:@"???"];
	                break;
	        }
	        for(UInt8 i = 0; i < canMessage.LEN; i++)
	        {
	            [textData appendFormat:@"%02x ",canMessage.DATA[i]];
	            [textAscii appendFormat:@"%c ",(canMessage.DATA[i] < 32)? '.' : canMessage.DATA[i]];
	        }
	        timeStamp = ((((UInt64)canTimestamp.millis_overflow * (UInt32)4294967295) + (UInt64)canTimestamp.millis) * 1000) + ((UInt64)canTimestamp.micros);
	        if(firstTime)
	        {
	            lastStamp = timeStamp;
	            firstTime = 0;
	        }
	        switch(modeTimestamp)
	        {
	            case TIME_ZERO:
	                microseconds = timeStamp - lastStamp;
	                break;
	            case TIME_REL:
	                microseconds = timeStamp - lastStamp;
	                lastStamp = timeStamp;
	                break;
	            default:
	                microseconds = timeStamp;
	                break;
	        }
	        microseconds %= (24LLU * 60LLU * 60LLU * 1000LLU * 1000LLU);
	        [textTimestamp appendFormat:@"%2llu:",microseconds / (60LLU * 60LLU * 1000LLU * 1000LLU)];
	        microseconds %= (60LLU * 60LLU * 1000LLU * 1000LLU);
	        [textTimestamp appendFormat:@"%02llu:",microseconds / (60LLU * 1000LLU * 1000LLU)];
	        microseconds %= (60LLU * 1000LLU * 1000LLU);
	        [textTimestamp appendFormat:@"%02llu.",microseconds / (1000LLU * 1000LLU)];
	        microseconds %= (1000LLU * 1000LLU);
	        [textTimestamp appendFormat:@"%03llu.",microseconds / (1000LLU)];
	        microseconds %= (1000LLU);
	        [textTimestamp appendFormat:@"%03llu",microseconds];
	        
	        CANMessage *newMessage = [[CANMessage alloc] init];
	        [newMessage setNumber:[NSString stringWithFormat:@"%llu",frameCounter++]];
	        [newMessage setTimestamp:textTimestamp];
	        [newMessage setIdentifier:[NSString stringWithFormat:@"%03lx",canMessage.ID]];
	        [newMessage setType:textType];
	        [newMessage setData:textData];
	        [newMessage setAscii:textAscii];
	        [arrayController addObject:newMessage];
	        r = 0;
            n++;
	        
	        /* [MACCAN-2] */
	        if(result == PCAN_ERROR_OK) {
				if(!(canMessage.MSGTYPE & PCAN_MESSAGE_STATUS)) {
					value = 0LL;
					if(canMessage.LEN >= 1)
						value |= (long long)canMessage.DATA[0] << 0;
					if(canMessage.LEN >= 2)
						value |= (long long)canMessage.DATA[1] << 8;
					if(canMessage.LEN >= 3)
						value |= (long long)canMessage.DATA[2] << 16;
					if(canMessage.LEN >= 4)
						value |= (long long)canMessage.DATA[3] << 24;
					if(canMessage.LEN >= 5)
						value |= (long long)canMessage.DATA[4] << 32;
					if(canMessage.LEN >= 6)
						value |= (long long)canMessage.DATA[5] << 40;
					if(canMessage.LEN >= 7)
						value |= (long long)canMessage.DATA[6] << 48;
					if(canMessage.LEN >= 8)
						value |= (long long)canMessage.DATA[7] << 56;
					if(value != expected) {
						if((value - expected) < 0)
							NSLog(@"@%llu - old message(s) in the URB (offset=%lli)", frameCounter - 1, value - expected);
						else
							NSLog(@"@%llu - %lli message(s) lost or overwritten", frameCounter - 1, value - expected);
						expected = value;
					}
					expected++;
	            }
	        }
	    }
        duration = mach_absolute_time() - start;
        /* convert to nanoseconds */
        duration *= info.numer;
        duration /= info.denom;
        
    } while((result == PCAN_ERROR_OK) && (duration < 10000000));
    
    if(result != PCAN_ERROR_OK)
    {
        //uint64_t s = mach_absolute_time();
        
        NSUInteger arrayCount = [[arrayController arrangedObjects] count];
        
        if(arrayCount > MAX_CAN_MESSAGES)
        {
            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, arrayCount-MAX_CAN_MESSAGES)];
            [arrayController removeObjectsAtArrangedObjectIndexes:indexSet];
            
            //uint64_t d = mach_absolute_time() - s;
            //NSLog(@"remove = %lluns for %lu object(s)",((d*info.numer)/info.denom),arrayCount-MAX_CAN_MESSAGES);
        }
    }
    //else
    //    NSLog(@"%3d frame(s) in %lluns",n,duration);
    /* why? */
    if(r < 3)
    {
        [tableView scrollRowToVisible:[tableView selectedRow]];
        r++;
    }
}
@end
