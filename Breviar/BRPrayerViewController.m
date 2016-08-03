//
//  BRPrayerViewController.m
//  Breviar
//
//  Created by Gyimesi Akos on 9/7/12.
//
//

#import "BRPrayerViewController.h"
#import "BRSettings.h"
#import "BRCGIQuery.h"
#import "BRUtil.h"
#import "GAI.h"
#import "GAIFields.h"
#import "GAIDictionaryBuilder.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface BRPrayerViewController ()

@property (strong, nonatomic) BRPrayerViewController *subpageController;
@property (strong, nonatomic) AVSpeechSynthesizer *speechSynthesizer;

@end

@implementation BRPrayerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    // If we are coming from a subpage, move its shared webview here
    if (self.subpageController) {
        self.webView = self.subpageController.webView;
        [self setupSharedWebView];
    }
    
    // The body will get generated on demand, if it hasn't been already generated by previous request
    [self setHtmlBody:self.prayer.body forPrayer:self.prayer.queryId];
    
    [super viewWillAppear:animated];
    
    self.navigationItem.title = self.prayer.title;
    
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self updateNightModeButtonTitle];
    [self updateFontItems];

    self.speechSynthesizer = nil;

    // Google Analytics
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    [tracker set:kGAIScreenName value:[NSString stringWithFormat:@"Prayer/%@", self.prayer.prayerName]];
    [tracker send:[[GAIDictionaryBuilder createScreenView] build]];
    
    // Start audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:YES error:nil];
    
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand addTarget:self action:@selector(playSpeaker:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(pauseSpeaker:)];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(toggleSpeaker:)];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    self.prayer.scrollOffset = self.webView.scrollView.contentOffset.y;
    self.prayer.scrollHeight = self.webView.scrollView.contentSize.height;
    
    if (self.speechSynthesizer.speaking) {
        [self.speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    // Stop audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:NO error:nil];
    
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.togglePlayPauseCommand removeTarget:self];

    [super viewDidDisappear:animated];
}

- (void)setHtmlBody:(NSString *)body forPrayer:(NSString *)prayerId
{
    self.htmlContent = [NSString stringWithFormat:@"<div id=\"prayer-%@\">%@</div>", prayerId, body];
}

- (IBAction)toggleNightMode:(id)sender
{
    BOOL nightMode = [[BRSettings instance] boolForOption:@"of2nr"];
    [[BRSettings instance] setBool:!nightMode forOption:@"of2nr"];
    [self updateNightModeButtonTitle];
    [self refreshPrayer];
}

- (void)updateNightModeButtonTitle
{
    BOOL nightMode = [[BRSettings instance] boolForOption:@"of2nr"];
    self.nightModeItem.image = nightMode ? [UIImage imageNamed:@"night_mode_on"] : [UIImage imageNamed:@"night_mode_off"];
}

- (IBAction)playSpeaker:(id)sender
{
    if (self.speechSynthesizer.paused) {
        [self.speechSynthesizer continueSpeaking];
    }
    else {
        self.speakItem.enabled = NO;
        self.speakItem.image = [UIImage imageNamed:@"speaker_on"];
        
        BOOL oldValue = [[BRSettings instance] boolForOption:@"of0bf"];
        if (oldValue == NO) {
            // We're setting the blind-friendly option to YES because updateWebViewContent adds CSS tags based on this global singleton; an ugly hack, for which I appologize :) (Oto Kominak)
            [[BRSettings instance] setBool:YES forOption:@"of0bf"];
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSString *body = self.prayer.bodyForSpeechSynthesis;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
                [self setHtmlBody:body forPrayer:self.prayer.queryId];
                [self updateWebViewContent];
                
                if (oldValue == NO) {
                    // Setting it back - and the hack's done.
                    [[BRSettings instance] setBool:NO forOption:@"of0bf"];
                }
            });
        });
    }
    
    self.speakItem.image = [UIImage imageNamed:@"speaker_on"];
}

- (IBAction)pauseSpeaker:(id)sender
{
    [self.speechSynthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    self.speakItem.image = [UIImage imageNamed:@"speaker_off"];
}

- (IBAction)toggleSpeaker:(id)sender
{
    if (self.speechSynthesizer.speaking) {
        [self pauseSpeaker:sender];
    }
    else {
        [self playSpeaker:sender];
    }
    
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [super webViewDidFinishLoad:webView];
    
    if (self.prayer.scrollOffset > 0 && self.prayer.scrollHeight > 0) {
        CGFloat height = self.webView.scrollView.contentSize.height;
        CGFloat maxOffset = height - self.webView.frame.size.height;
        CGFloat scrollOffset = self.prayer.scrollOffset * height / self.prayer.scrollHeight;
        self.webView.scrollView.contentOffset = CGPointMake(0, MIN(scrollOffset, maxOffset));
    }
    
    // An instance of AVSpeechSynthesizer must be initialized before loading content in web view
    if (self.speechSynthesizer && !self.speechSynthesizer.speaking) {
        NSString *webViewString = [self.webView stringByEvaluatingJavaScriptFromString:@"(function (){ return document.body.innerText; })();"];
        
        NSString *selectedLanguage = [[BRSettings instance] stringForOption:@"j"];
        NSDictionary *voiceCodes = @{
            @"sk": @"sk-SK",
            @"cz": @"cs-CZ",
            @"hu": @"hu-HU",
        };
        NSString *voiceCode = voiceCodes[selectedLanguage];
        if (!voiceCode) {
            voiceCode = @"sk-SK";
        }
        
        AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:voiceCode];
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:webViewString];
        utterance.voice = voice;
        
        NSString *speechRate = [[BRSettings instance] stringForOption:@"speechRate"];
        if ([speechRate isEqualToString:@"verySlow"]) {
            utterance.rate = (AVSpeechUtteranceMinimumSpeechRate * 3 + AVSpeechUtteranceMaximumSpeechRate * 1) / 4;
        } else if ([speechRate isEqualToString:@"slow"]) {
            utterance.rate = (AVSpeechUtteranceMinimumSpeechRate * 2 + AVSpeechUtteranceMaximumSpeechRate * 1) / 3;
        } else if ([speechRate isEqualToString:@"fast"]) {
            utterance.rate = (AVSpeechUtteranceMinimumSpeechRate * 3 + AVSpeechUtteranceMaximumSpeechRate * 4) / 7;
        } else if ([speechRate isEqualToString:@"veryFast"]) {
            utterance.rate = (AVSpeechUtteranceMinimumSpeechRate * 1 + AVSpeechUtteranceMaximumSpeechRate * 3) / 4;
        } else {
            utterance.rate = (AVSpeechUtteranceMinimumSpeechRate * 1 + AVSpeechUtteranceMaximumSpeechRate * 1) / 2;
        }
        
        [self.speechSynthesizer speakUtterance:utterance];
        
        self.speakItem.enabled = YES;
    }
}

- (IBAction)increaseFontSize:(id)sender
{
    [self modifyFontSize:+2];
}

- (IBAction)decreaseFontSize:(id)sender
{
    [self modifyFontSize:-2];
}

- (void)modifyFontSize:(NSInteger)sizeDiff
{
    BRSettings *settings = [BRSettings instance];
    settings.prayerFontSize += sizeDiff;
    [self refreshPrayer];
    [self updateFontItems];
}

- (void)updateFontItems
{
    BRSettings *settings = [BRSettings instance];
    self.increaseFontItem.enabled = (settings.prayerFontSize < BR_MAX_FONT_SIZE);
    self.decreaseFontItem.enabled = (settings.prayerFontSize > BR_MIN_FONT_SIZE);
}

- (void)refreshPrayer
{
    self.prayer.scrollOffset = self.webView.scrollView.contentOffset.y;
    self.prayer.scrollHeight = self.webView.scrollView.contentSize.height;
    [self setHtmlBody:self.prayer.body forPrayer:self.prayer.queryId];
    [self updateWebViewContent];
}

#pragma mark -
#pragma mark Handling subpages

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if ([request.URL.absoluteString rangeOfString:@".cgi?"].location != NSNotFound) {
        // Parse URL
        NSArray *argList = [request.URL.query componentsSeparatedByString:@"&"];
        NSMutableDictionary *args = [[NSMutableDictionary alloc] init];
        for (NSString *kv in argList) {
            NSArray *kvParts = [kv componentsSeparatedByString:@"="];
            NSString *k = [kvParts objectAtIndex:0];
            NSString *v = [kvParts objectAtIndex:1];
            [args setObject:v forKey:k];
        }
        
        // Parse static text query
        NSString *staticTextId = [args objectForKey:@"st"];
        if (!staticTextId) {
            return NO;
        }
        BRPrayer *prayer = [BRPrayer prayerForStaticTextId:staticTextId];
        
        // Push subpage
        self.subpageController = [self.storyboard instantiateViewControllerWithIdentifier:@"PrayerViewController"];
        self.subpageController.webView = self.webView;
        self.subpageController.prayer = prayer;

        [UIApplication sharedApplication].statusBarHidden = NO;
        self.navigationController.navigationBarHidden = NO;
        self.navigationController.navigationBar.alpha = 1.0;
        self.navigationController.toolbarHidden = NO;
        self.navigationController.toolbar.alpha = 1.0;

        [self.navigationController pushViewController:self.subpageController animated:YES];
        
        return NO;
    }
    else {
        return [super webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
    }
}

@end
