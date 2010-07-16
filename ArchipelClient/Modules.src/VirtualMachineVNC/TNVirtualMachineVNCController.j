/*
 * TNViewHypervisorControl.j
 *
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import <AppKit/CPWebView.j>


/*! @defgroup  virtualmachinevnc Module VirtualMachineVNC 
    @desc This module allows to access to virtual machine displays
    using VNC.
*/


/*! @ingroup virtualmachinevnc
    @group TNArchipelTypeVirtualMachineControl
    namespave of vm control
*/
TNArchipelTypeVirtualMachineControl             = @"archipel:vm:control";

/*! @ingroup virtualmachinevnc
    @group TNArchipelTypeVirtualMachineControl
    get vnc display
*/
TNArchipelTypeVirtualMachineControlVNCDisplay   = @"vncdisplay";

TNArchipelVNCScaleFactor                        = @"TNArchipelVNCScaleFactor_";


/*! @ingroup virtualmachinevnc
    module that allow to access virtual machine console using VNC
*/
@implementation TNVirtualMachineVNCController : TNModule
{
    @outlet CPScrollView    mainScrollView;
    @outlet CPTextField     fieldJID;
    @outlet CPTextField     fieldName;
    @outlet CPView          maskingView;
    @outlet CPSlider        sliderScaling;
    @outlet CPButton        buttonFullscreen;

    CPString                _url;
    CPString                _VMHost;
    CPString                _vncDisplay;
    CPString                _webServerPort;
    CPWebView               _vncWebView;
    CPWebView               _vncWebViewForWindow;
}

/*! initialize some value at CIB awakening
*/
- (void)awakeFromCib
{
    [fieldJID setSelectable:YES];
    
    var imageFullscreen = [[CPImage alloc] initWithContentsOfFile:[[CPBundle mainBundle] pathForResource:@"button-icons/button-icon-fullscreen.png"] size:CPSizeMake(16, 16)]
    [buttonFullscreen setImage:imageFullscreen];
    _webServerPort   = [[CPBundle bundleForClass:[self class]] objectForInfoDictionaryKey:@"ArchipelServerSideWebServerPort"];

    _vncWebView = [[CPWebView alloc] initWithFrame:[mainScrollView bounds]];
    [_vncWebView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    
    [mainScrollView setDocumentView:_vncWebView];
    [mainScrollView setAutohidesScrollers:YES];
    [sliderScaling setContinuous:NO];
}

/*! TNModule implementation
*/
- (void)willLoad
{
    [super willLoad];
    
    var center = [CPNotificationCenter defaultCenter];   
    [center addObserver:self selector:@selector(didNickNameUpdated:) name:TNStropheContactNicknameUpdatedNotification object:_entity];
    [center postNotificationName:TNArchipelModulesReadyNotification object:self];
    [center addObserver:self selector:@selector(didPresenceUpdated:) name:TNStropheContactPresenceUpdatedNotification object:_entity];
    
    var viewBounds = [[self view] bounds];
    viewBounds.size.height = 1000;
    [[self view] setFrame:viewBounds];
}

/*! TNModule implementation
*/
- (void)willShow
{
    [super willShow];

    [maskingView setFrame:[[self view] bounds]];
    
    [fieldName setStringValue:[_entity nickname]];
    [fieldJID setStringValue:[_entity JID]];
    [self checkIfRunning];
}

/*! TNModule implementation
*/
- (void)willHide
{
    [super willHide];

    var bundle = [CPBundle bundleForClass:[self class]];

    [_vncWebView setMainFrameURL:[bundle pathForResource:@"empty.html"]];
    //[_vncWebView removeFromSuperview];
}

/*! TNModule implementation
*/
- (void)willUnload
{
    [super willUnload];
}

- (void)didNickNameUpdated:(CPNotification)aNotification
{
    if ([aNotification object] == _entity)
    {
       [fieldName setStringValue:[_entity nickname]]
    }
}
/*! send stanza to get the current virtual machine VNC display
*/

- (void)didPresenceUpdated:(CPNotification)aNotification
{
    [self checkIfRunning];
}

- (void)checkIfRunning
{
    if ([_entity XMPPShow] == TNStropheContactStatusOnline)
    {
        [maskingView removeFromSuperview];
        [self getVirtualMachineVNCDisplay];
    }
    else
    {
        [maskingView setFrame:[[self view] bounds]];
        [[self view] addSubview:maskingView];
    }
}


- (void)getVirtualMachineVNCDisplay
{
    var stanza   = [TNStropheStanza iqWithType:@"get"];
    
    [stanza addChildName:@"query" withAttributes:{"xmlns": TNArchipelTypeVirtualMachineControl}];
    [stanza addChildName:@"archipel" withAttributes:{
        "action": TNArchipelTypeVirtualMachineControlVNCDisplay}];
                
    [_entity sendStanza:stanza andRegisterSelector:@selector(_didReceiveVNCDisplay:) ofObject:self];
}

/*! message sent when VNC display info is received
    @param aStanza the response stanza
*/
- (void)_didReceiveVNCDisplay:(id)aStanza
{
    if ([aStanza getType] == @"result")
    {
        var bundle      = [CPBundle bundleForClass:self];
        var displayNode = [aStanza firstChildWithName:@"vncdisplay"];
        var defaults    = [TNUserDefaults standardUserDefaults];
        var key         = TNArchipelVNCScaleFactor + [[self entity] JID];
        var lastScale   = [defaults objectForKey:key];
        _vncDisplay     = [displayNode valueForAttribute:@"proxy"];
        _VMHost         = [displayNode valueForAttribute:@"host"];
        
        
        _url = @"http://" + _VMHost + @":" + _webServerPort + @"/index.html?host="+ _VMHost  +"&port=" + _vncDisplay;
        // var path = [bundle pathForResource:@"index.html"];
        // path += @"?host="+ _VMHost  + @"&port=" + _vncDisplay
        
        if (lastScale)
        {
            [sliderScaling setValue:lastScale];
            _url += @"&scaling=" + lastScale;
        }
        else
            [sliderScaling setValue:100];
        
        [_vncWebView setFrameLoadDelegate:self];
        
        [_vncWebView setMainFrameURL:_url];
        [_vncWebView setMainFrameURL:path];
    }
    else if ([aStanza getType] == @"error")
    {
        [self handleIqErrorFromStanza:aStanza];
    }
}

- (void)webView:(CPWebView)aWebView didFinishLoadForFrame:(id)aFrame
{
    _vncWebView._iframe.focus()  
}

- (IBAction)openInNewWindow:(id)sender
{
    var winFrame        = CGRectMake(100,100, 800, 600);
    var pfWinFrame      = CGRectMake(100,100, 800, 600);
    var scrollFrame     = CGRectMake(0,0, 800, 600);
    
    var VNCWindow           = [[CPWindow alloc] initWithContentRect:winFrame styleMask:CPTitledWindowMask|CPClosableWindowMask|CPMiniaturizableWindowMask|CPResizableWindowMask|CPBorderlessBridgeWindowMask];
    var scrollView          = [[CPScrollView alloc] initWithFrame:CGRectMakeZero()];
    var platformVNCWindow   = [[CPPlatformWindow alloc] initWithContentRect:pfWinFrame];
    
    var vncWebViewForWindow = [[CPWebView alloc] initWithFrame:[mainScrollView bounds]];
    
    [vncWebViewForWindow setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [vncWebViewForWindow setMainFrameURL:@"http://" + _VMHost + @":" + _webServerPort + @"?port=" + _vncDisplay + "&host="+_VMHost];
    
    [[VNCWindow contentView] addSubview:vncWebViewForWindow];
    [VNCWindow setPlatformWindow:platformVNCWindow];
    [VNCWindow setDelegate:self];
    [VNCWindow setTitle:@"Display for " + [_entity nickname]];
    // [platformVNCWindow setTitle:@"Display for " + [_entity nickname]];
    //[scrollView setFrame:[[VNCWindow contentView] bounds]];
    [vncWebViewForWindow setFrame:[[VNCWindow contentView] bounds]];
    
    [VNCWindow orderFront:nil];
    [platformVNCWindow orderFront:nil];
}

- (IBAction)changeScale:(id)sender
{
    if (_url)
    {
        var defaults = [TNUserDefaults standardUserDefaults];
        
        _url = @"http://" + _VMHost + @":" + _webServerPort + @"/index.html?host="+ _VMHost  +"&port=" + _vncDisplay + "&scaling=" + [sliderScaling intValue];
        
        var key = TNArchipelVNCScaleFactor + [[self entity] JID];
        [defaults setObject:[sliderScaling intValue] forKey:key];
        [_vncWebView setMainFrameURL:_url];
    }
}

@end



