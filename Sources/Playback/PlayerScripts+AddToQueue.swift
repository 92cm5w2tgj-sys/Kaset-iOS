import Foundation

extension PlayerScripts {
    /// Appends a song to the end of the page's queue.
    ///
    /// Same mechanism as `playNext` (kaset `queueInjectionScript`): the player bar's own menu
    /// carries a `queueAddEndpoint` item; its target video is substituted for the click and
    /// restored. Here the item is the one inserting at the end of the queue, and success is
    /// confirmed by reading the page's queue model back. Result arrives as `queueResult`.
    static func addToQueue(videoId: String, attempt: Int = 0) -> String {
        """
        (function(targetVideoId) {
            const bridge = window.webkit && window.webkit.messageHandlers
                && window.webkit.messageHandlers.\(self.bridgeName);
            \(self.playerBarLookup)
            const startedAt = Date.now();
            let done = false;
            let observer = null;
            let didOpenMenu = false;

            function report(success, reason) {
                if (done) return;
                done = true;
                if (observer) { observer.disconnect(); observer = null; }
                if (didOpenMenu) { didOpenMenu = false; try { document.body.click(); } catch (_) {} }
                try {
                    if (bridge) {
                        bridge.postMessage({
                            kind: 'queueResult', op: 'add', videoId: targetVideoId,
                            attemptGeneration: \(attempt),
                            success: !!success, reason: reason || ''
                        });
                    }
                } catch (_) {}
            }

            function firstVideoId(root) {
                const seen = new Set();
                function visit(value, depth) {
                    if (!value || typeof value !== 'object' || depth > 7 || seen.has(value)) return '';
                    seen.add(value);
                    for (const [key, child] of Object.entries(value)) {
                        if ((key === 'videoId' || key === 'video_id') && typeof child === 'string' && child) return child;
                    }
                    for (const child of Object.values(value)) {
                        const found = visit(child, depth + 1);
                        if (found) return found;
                    }
                    return '';
                }
                return visit(root, 0);
            }

            function queueIds() {
                return Array.from(document.querySelectorAll('ytmusic-player-queue-item'))
                    .map(el => firstVideoId(el.data || el.__data || null));
            }

            function findAddItem(items) {
                const list = Array.from(items);
                const byEndpoint = list.find(item => {
                    const data = item.data || item.__data || null;
                    const endpoint = data && (data.serviceEndpoint || data.navigationEndpoint || data.endpoint);
                    const add = endpoint && endpoint.queueAddEndpoint;
                    return !!add && add.queueInsertPosition === 'INSERT_AT_END';
                });
                if (byEndpoint) return byEndpoint;
                return list.find(item => /add to queue|ajouter à la file/i.test(item.textContent || '')) || null;
            }

            const idsBefore = queueIds();

            function dispatchFrom(items) {
                const item = findAddItem(items);
                if (!item) { report(false, 'add-to-queue-item-not-found'); return; }
                const data = item.data || item.__data || null;
                const endpoint = data && (data.serviceEndpoint || data.navigationEndpoint || data.endpoint);
                const add = endpoint && endpoint.queueAddEndpoint;
                const target = add && add.queueTarget;
                if (!target || typeof target.videoId !== 'string' || typeof item.click !== 'function') {
                    report(false, 'add-to-queue-endpoint-unavailable');
                    return;
                }
                const original = target.videoId;
                const onEmpty = target.onEmptyQueue && target.onEmptyQueue.watchEndpoint;
                const originalOnEmpty = onEmpty && onEmpty.videoId;
                target.videoId = targetVideoId;
                if (onEmpty) onEmpty.videoId = targetVideoId;
                try { item.click(); } catch (_) {
                    target.videoId = original;
                    if (onEmpty) onEmpty.videoId = originalOnEmpty;
                    report(false, 'add-to-queue-click-threw');
                    return;
                }
                setTimeout(() => {
                    target.videoId = original;
                    if (onEmpty) onEmpty.videoId = originalOnEmpty;
                }, 0);

                const verifyStartedAt = Date.now();
                (function verify() {
                    if (done) return;
                    const ids = queueIds();
                    if (ids.length > idsBefore.length && ids.includes(targetVideoId)) {
                        report(true, 'queue-readback-confirmed');
                        return;
                    }
                    if (Date.now() - verifyStartedAt > 6000) {
                        report(false, 'queue-readback-timeout');
                        return;
                    }
                    setTimeout(verify, 150);
                })();
            }

            function openMenu() {
                if (done) return;
                const bar = __kasetPlayerBar();
                const button = bar && (__kasetPlayerBarElement('menu', bar)
                    || bar.querySelector('ytmusic-menu-renderer button, ytmusic-menu-renderer tp-yt-paper-icon-button'));
                if (!button) {
                    if (Date.now() - startedAt < 8000) { setTimeout(openMenu, 150); return; }
                    report(false, 'player-bar-menu-not-found');
                    return;
                }
                let inspected = false;
                function tryDispatch() {
                    if (done || inspected) return;
                    const items = document.querySelectorAll('ytmusic-menu-popup-renderer ytmusic-menu-service-item-renderer');
                    if (items.length === 0) return;
                    inspected = true;
                    if (observer) { observer.disconnect(); observer = null; }
                    dispatchFrom(items);
                }
                observer = new MutationObserver(tryDispatch);
                observer.observe(document.body, { childList: true, subtree: true });
                didOpenMenu = true;
                setTimeout(() => report(false, 'menu-timeout'), 5000);
                button.click();
                setTimeout(tryDispatch, 0);
            }
            openMenu();
        })(\(self.literal(videoId)));
        """
    }
}
