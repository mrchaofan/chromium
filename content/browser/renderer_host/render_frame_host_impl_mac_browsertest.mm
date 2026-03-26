// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "content/browser/renderer_host/render_frame_host_impl.h"

#include "base/mac/scoped_nsobject.h"
#include "base/run_loop.h"
#include "content/browser/renderer_host/render_widget_host_view_mac.h"
#include "content/browser/web_contents/web_contents_impl.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/content_browser_test.h"
#include "content/public/test/content_browser_test_utils.h"
#include "content/shell/browser/shell.h"
#include "testing/gtest_mac.h"
#include "ui/base/cocoa/find_pasteboard.h"
#include "url/gurl.h"

namespace content {

using RenderFrameHostImplBrowserMacTest = ContentBrowserTest;

IN_PROC_BROWSER_TEST_F(RenderFrameHostImplBrowserMacTest,
                       CopyToFindPasteboard) {
  WebContents* web_contents = shell()->web_contents();

  GURL url("data:text/html,Hello world");
  ASSERT_TRUE(NavigateToURL(web_contents, url));

  FindPasteboard* pboard = [FindPasteboard sharedInstance];
  base::scoped_nsobject<NSString> original_pboard_text(
      [[pboard findText] copy]);

  [pboard setFindText:@"test"];
  EXPECT_NSEQ(@"test", [pboard findText]);

  auto* input_handler = static_cast<WebContentsImpl*>(web_contents)
                            ->GetFocusedFrameWidgetInputHandler();
  input_handler->SelectAll();
  input_handler->CopyToFindPboard();

  base::RunLoop loop;
  __block base::OnceClosure quit_closure = loop.QuitClosure();

  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  id notification_handle =
      [center addObserverForName:kFindPasteboardChangedNotification
                          object:pboard
                           queue:nil
                      usingBlock:^(NSNotification*) {
                        std::move(quit_closure).Run();
                      }];
  loop.Run();

  [center removeObserver:notification_handle];

  EXPECT_NSEQ(@"Hello world", [pboard findText]);

  [pboard setFindText:original_pboard_text];
}

// Confirms that on macOS, each webpage (WebContents) corresponds to exactly
// one NSView for display and event input handling.
IN_PROC_BROWSER_TEST_F(RenderFrameHostImplBrowserMacTest,
                       MainFrameHasNSView) {
  WebContents* web_contents = shell()->web_contents();

  GURL url("data:text/html,<p>Hello world</p>");
  ASSERT_TRUE(NavigateToURL(web_contents, url));

  RenderFrameHost* main_frame = web_contents->GetMainFrame();
  ASSERT_TRUE(main_frame);

  // Each webpage's main frame must have a non-null native view (NSView).
  gfx::NativeView native_view = main_frame->GetNativeView();
  EXPECT_TRUE(native_view.GetNativeNSView() != nil);
}

// Confirms that GetNativeView() on a RenderFrameHost returns the NSView
// associated with that frame's RenderWidgetHost, not always the main frame's
// NSView.  For a main frame, the NSView returned by GetNativeView() must match
// the one obtained through the frame's RenderWidgetHostView.
IN_PROC_BROWSER_TEST_F(RenderFrameHostImplBrowserMacTest,
                       MainFrameNSViewMatchesRenderWidgetHostView) {
  WebContents* web_contents = shell()->web_contents();

  GURL url("data:text/html,<p>Hello world</p>");
  ASSERT_TRUE(NavigateToURL(web_contents, url));

  RenderFrameHost* main_frame = web_contents->GetMainFrame();
  ASSERT_TRUE(main_frame);

  // GetNativeView() on the main frame should return the same NSView as
  // obtained via GetView()->GetNativeView().
  RenderWidgetHostView* rwhv = main_frame->GetView();
  ASSERT_TRUE(rwhv);
  NSView* rwhv_ns_view = rwhv->GetNativeView().GetNativeNSView();
  NSView* frame_ns_view = main_frame->GetNativeView().GetNativeNSView();

  EXPECT_EQ(rwhv_ns_view, frame_ns_view);
}

}  // namespace content
