//
//  ChirpyShield.swift
//  Chirpy Browser — engine 0.39.2 (Swift)
//
//  The Shield: Chirpy's gate, standing in the
//  fetcher itself. Every request the engine
//  issues — a page, a form post, a picture, a
//  stylesheet — is asked of the Shield before
//  any network I/O happens. Two bundled lists
//  of domains, matched by host: the advertising
//  and tracking list, and the family list. The
//  family filter is ON by default and has NO
//  off switch — that is Tyler's standing word,
//  and the home page promises it out loud. The
//  Shield sends no third-party cookies and
//  tells no one where Chirpy has been: no
//  telemetry, ever.
//
//  This file was ChirpyEngine.swift's Shield
//  section — everything from the MARK that
//  stood over it down to the end of
//  tbShieldPrivacy — until 0.39.2, when it
//  moved here whole: the second step of
//  splitting the codebase into files of their
//  own, at Tyler's direction, so each part can
//  be fixed and built quicker. Nothing in the
//  move changed the Shield itself; the section
//  intro that stood over it in the engine file
//  stands below, as it was written.
//  ChirpyEngine.swift keeps a short marker
//  where the section lived, pointing here.
//
//  Public domain (Unlicense), like the rest
//  of Chirpy.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - The Shield (0.28)


// The Shield: Chirpy's gate, standing in the fetcher
// itself. Every request this engine issues — a page, a
// form post, a picture, a stylesheet — is built by one
// of the fetch helpers below, and each helper asks the
// Shield before any network I/O happens. Two bundled
// lists of domains, matched by host: a request whose
// host IS a listed domain, or sits under one (any
// subdomain of it), is refused.
//
// A refused page load becomes the block page further
// down — a calm word about what was stopped and why.
// A refused subresource simply never arrives: the
// picture keeps its label, the sheet is skipped, the
// same fallback a failed fetch has always taken.
//
// The lists are data, and plainly commented, so they
// can grow: add a domain on its own line, without a
// scheme and without wildcards. They are curated
// starters — the majors a family browser actually
// meets — not the whole of EasyList or any public
// corpus, and the README says so.
//
// The family filter has NO off switch. That is
// Tyler's standing word, and the home page promises
// it out loud: "on on purpose, not buried in a
// settings page."

enum TBShieldCategory {
    case advertising   // advertising & tracking networks
    case family        // adult & gambling sites
}

// Advertising and tracking: the ad networks, the
// exchanges, the analytics and session-replay
// services, the affiliate and attribution trackers —
// the machinery that follows a reader around the web.
let TBShieldAdDomains: Set<String> = [
    // Google's advertising and measurement
    "doubleclick.net", "googlesyndication.com",
    "googleadservices.com", "googletagservices.com",
    "google-analytics.com", "googletagmanager.com",
    // Social and platform trackers (the parent social
    // sites themselves are NOT listed — only their
    // advertising and pixel hosts)
    "facebook.net", "pixel.facebook.com",
    "ads.twitter.com", "analytics.twitter.com",
    "ads.linkedin.com", "ads.pinterest.com",
    "ct.pinterest.com", "analytics.pinterest.com",
    "ads.tiktok.com", "analytics.tiktok.com",
    "ads.snapchat.com", "tr.snapchat.com",
    "ads.reddit.com", "ads.yahoo.com",
    "bat.bing.com", "clarity.ms",
    // Exchanges, supply and demand platforms
    "adnxs.com", "appnexus.com", "adsrvr.org",
    "rubiconproject.com", "pubmatic.com", "openx.net",
    "criteo.com", "criteo.net", "media.net",
    "amazon-adsystem.com", "smartadserver.com",
    "adform.net", "contextweb.com", "pulsepoint.com",
    "sharethrough.com", "triplelift.com", "gumgum.com",
    "kargo.com", "nativo.com", "sovrn.com", "lijit.com",
    "indexexchange.com", "casalemedia.com",
    "bidswitch.net", "districtm.io", "rtbhouse.com",
    "yieldlab.net", "yieldmo.com", "teads.com",
    "teads.tv", "seedtag.com", "playwire.com",
    "freestar.io", "mediavine.com", "adthrive.com",
    "raptive.com", "snigel.com", "setupad.com",
    "connatix.com", "stackadapt.com", "simpli.fi",
    "basis.net", "choozle.com",
    // Native and content-recommendation networks
    "taboola.com", "outbrain.com", "mgid.com",
    "revcontent.com", "contentad.net", "adnow.com",
    "adskeeper.com", "advertising.com", "adblade.com",
    "plista.com", "ligatus.com", "adyoulike.com",
    // Pop, push and aggressive networks
    "popads.net", "popcash.net", "propellerads.com",
    "adsterra.com", "clickadu.com", "hilltopads.net",
    "adcash.com", "onclickads.net", "onclkds.com",
    "bidvertiser.com", "infolinks.com",
    "vibrantmedia.com", "admarketplace.com",
    "7search.com", "adhitz.com", "a-ads.com",
    "bitmedia.io", "coinzilla.com", "cointraffic.io",
    "evadav.com", "monetag.com", "galaksion.com",
    "mybid.io", "adsupply.com",
    // Adult advertising networks (the ads, here; the
    // destinations themselves are on the family list)
    "exoclick.com", "exosrv.com", "exdynsrv.com",
    "juicyads.com", "plugrush.com", "trafficjunky.com",
    "trafficstars.com", "adxpansion.com",
    "adspyglass.com",
    // Video advertising
    "spotxchange.com", "spotx.tv", "springserve.com",
    "fwmrm.net", "telaria.com", "tremorhub.com",
    "videology.com", "brightroll.com", "innovid.com",
    "flashtalking.com", "sizmek.com", "serving-sys.com",
    "aniview.com", "primis.tech",
    // Mobile advertising and attribution
    "applovin.com", "unityads.com", "ironsource.com",
    "ironsrc.com", "vungle.com", "chartboost.com",
    "mopub.com", "inmobi.com", "startapp.com",
    "airpush.com", "leadbolt.com",
    "millennialmedia.com", "smaato.com", "fyber.com",
    "loopme.com", "adcolony.com", "pangle.io",
    "mintegral.com", "liftoff.io", "moloco.com",
    "ogury.com", "appsflyer.com", "adjust.com",
    "kochava.com", "singular.net", "tune.com",
    "hasoffers.com",
    // Analytics, measurement and session replay
    "scorecardresearch.com", "quantserve.com",
    "quantcast.com", "chartbeat.com", "chartbeat.net",
    "parse.ly", "nr-data.net", "fullstory.com",
    "hotjar.com", "hotjar.io", "mouseflow.com",
    "luckyorange.com", "crazyegg.com", "clicktale.com",
    "clicktale.net", "smartlook.com", "logrocket.com",
    "segment.io", "cdn.segment.com",
    "api.amplitude.com", "api2.amplitude.com",
    "api.mixpanel.com", "heapanalytics.com",
    "woopra.com", "getclicky.com", "statcounter.com",
    "histats.com", "omtrdc.net", "demdex.net",
    "everesttech.net", "2o7.net", "imrworldwide.com",
    "crwdcntrl.net", "exelator.com", "exelate.com",
    "bluekai.com", "bkrtx.com", "mathtag.com",
    "d.turn.com", "addthis.com", "sharethis.com",
    "shareaholic.com", "po.st", "disqusads.com",
    "hs-analytics.net", "track.hubspot.com",
    "mktoresp.com", "marketo.net", "pi.pardot.com",
    "exacttarget.com", "track.customer.io",
    "sendgrid.net", "sessioncam.com",
    "decibelinsight.com", "quantummetric.com",
    "contentsquare.net", "inspectlet.com",
    "optimizely.com", "abtasty.com", "kameleoon.com",
    "dynamicyield.com", "visualwebsiteoptimizer.com",
    "foreseeresults.com", "iperceptions.com",
    "usabilla.com", "kampyle.com", "medallia.com",
    // Push-notification marketing
    "onesignal.com", "pushwoosh.com", "pushengage.com",
    "izooto.com", "aimtell.com", "foxpush.com",
    "pushcrew.com", "subscribers.com",
    // Identity, data brokers and ad verification
    "liveramp.com", "id5.io", "id5-sync.com",
    "tapad.com", "zeotap.com", "lotame.com",
    "agkn.com", "bombora.com", "demandbase.com",
    "rollworks.com", "6sense.com",
    "adsafeprotected.com", "integralads.com",
    "doubleverify.com", "moatads.com", "peer39.com",
    "grapeshot.com", "iesnare.com", "online-metrix.net",
    // Affiliate networks and their tracking domains
    "skimresources.com", "viglink.com", "awin1.com",
    "zanox.com", "tradedoubler.com", "linksynergy.com",
    "shareasale.com", "avantlink.com", "pepperjam.com",
    "impactradius.com", "partnerize.com", "qksrv.net",
    "tkqlhce.com", "dpbolvw.net", "jdoqocy.com",
    "anrdoezrs.net", "kqzyfj.com", "linkconnector.com",
    "adroll.com", "adroll.net", "nextroll.com",
    "perfectaudience.com", "steelhouse.com",
    // Ad servers and long-lived networks
    "zedo.com", "adzerk.net", "buysellads.com",
    "carbonads.net", "adspeed.com", "medialets.com",
    "unicast.com", "eyewonder.com", "pointroll.com",
    "bsserving.com", "undertone.com", "jivox.com",
    "mixpo.com", "adtheorent.com", "dstillery.com",
    "resonate.com", "dataxu.com", "mediamath.com",
    "netmining.com", "owneriq.com", "audiencex.com",
    "adara.com", "sojern.com", "intentmedia.net",
    // Regional majors
    "tanx.com", "mmstat.com", "pos.baidu.com",
    "hm.baidu.com", "mc.yandex.ru", "mc.yandex.com",
    "an.yandex.ru",
]

// The family filter: the major adult destinations
// and the major gambling destinations. On by
// default, on always — see the note at the top.
let TBShieldFamilyDomains: Set<String> = [
    // Adult video and photo destinations
    "pornhub.com", "xvideos.com", "xhamster.com",
    "xnxx.com", "redtube.com", "youporn.com",
    "tube8.com", "spankbang.com", "spankwire.com",
    "keezmovies.com", "extremetube.com",
    "pornerbros.com", "drtuber.com", "4tube.com",
    "fux.com", "alohatube.com", "porn300.com",
    "hclips.com", "sunporno.com", "hqporner.com",
    "porntrex.com", "porndoe.com", "porn.com",
    "sex.com", "motherless.com", "efukt.com",
    "pornpics.com", "pornhd.com", "youjizz.com",
    "empflix.com", "tnaflix.com", "eporner.com",
    "porndig.com", "thisvid.com", "boyfriendtv.com",
    "imagefap.com", "redgifs.com", "scrolller.com",
    "fapello.com",
    // Adult studios and membership sites
    "brazzers.com", "bangbros.com", "realitykings.com",
    "naughtyamerica.com", "digitalplayground.com",
    "twistys.com", "babes.com", "mofos.com",
    "teamskeet.com", "mylf.com", "fakehub.com",
    "pornpros.com", "blacked.com", "vixen.com",
    "tushy.com", "deeper.com", "slayed.com",
    "kink.com", "evilangel.com", "julesjordan.com",
    "metart.com", "x-art.com", "playboy.com",
    "penthouse.com", "hustler.com", "dorcel.com",
    "sexlikereal.com", "vrporn.com",
    // Live cams
    "chaturbate.com", "livejasmin.com", "stripchat.com",
    "bongacams.com", "myfreecams.com", "cam4.com",
    "imlive.com", "streamate.com", "xlovecam.com",
    "camsoda.com", "xcams.com", "flirt4free.com",
    "jerkmate.com", "liveprivates.com",
    "camcontacts.com",
    // Creator and clip platforms (adult)
    "onlyfans.com", "fansly.com", "manyvids.com",
    "clips4sale.com", "iwantclips.com", "loyalfans.com",
    "fancentro.com", "justfor.fans",
    // Drawn and written adult content
    "hanime.tv", "hentaihaven.xxx", "nhentai.net",
    "nhentai.com", "e-hentai.org", "exhentai.org",
    "hentai-foundry.com", "rule34.xxx", "paheal.net",
    "gelbooru.com", "danbooru.donmai.us", "xbooru.com",
    "sankakucomplex.com", "fakku.com", "hitomi.la",
    "tsumino.com", "pururin.io", "asmhentai.com",
    "hentaifox.com", "luscious.net", "8muses.com",
    "hentai2read.com", "simply-hentai.com",
    "doujins.com", "hentaihand.com", "3hentai.net",
    "hentaiera.com", "myhentaigallery.com",
    "literotica.com", "asstr.org", "sexstories.com",
    "nifty.org", "bdsmlibrary.com", "storiesonline.net",
    "lushstories.com",
    // Hookup, escort and adult personals
    "adultfriendfinder.com", "ashleymadison.com",
    "benaughty.com", "xdating.com", "freechatnow.com",
    "eros.com", "bedpage.com", "skipthegames.eu",
    "skipthegames.com", "rubmaps.ch",
    "theeroticreview.com", "eccie.net", "slixa.com",
    "tryst.link", "babepedia.com", "adamandeve.com",
    // Sportsbooks and bookmakers
    "bet365.com", "williamhill.com", "ladbrokes.com",
    "coral.co.uk", "paddypower.com", "skybet.com",
    "betfair.com", "betfred.com", "unibet.com",
    "unibet.co.uk", "betway.com", "betsson.com",
    "betsafe.com", "leovegas.com", "mrgreen.com",
    "rizk.com", "casumo.com", "videoslots.com",
    "comeon.com", "betclic.com", "winamax.com",
    "winamax.fr", "expekt.com", "nordicbet.com",
    "coolbet.com", "888.com", "888casino.com",
    "888poker.com", "draftkings.com", "fanduel.com",
    "betmgm.com", "caesars.com", "pointsbet.com",
    "espnbet.com", "betrivers.com",
    "playsugarhouse.com", "wynnbet.com",
    "hardrockbet.com", "betparx.com",
    "goldennuggetcasino.com", "borgatacasino.com",
    "palacasino.com", "resortscasino.com",
    "hardrockcasino.com",
    // Offshore and crypto books and casinos
    "bovada.lv", "betonline.ag", "sportsbetting.ag",
    "mybookie.ag", "bookmaker.eu", "betus.com",
    "xbet.ag", "superslots.ag", "wildcasino.ag",
    "slots.lv", "cafecasino.lv", "ignitioncasino.eu",
    "stake.com", "stake.us", "rollbit.com", "bc.game",
    "duelbits.com", "roobet.com", "cloudbet.com",
    "sportsbet.io", "bitsler.com", "primedice.com",
    "freebitco.in", "fortunejack.com", "bitstarz.com",
    "playamo.com", "gamdom.com", "csgoempire.com",
    "hellcase.com", "key-drop.com", "skinclub.com",
    "csgo500.com", "thunderpick.io", "ggbet.com",
    "loot.bet", "1xbet.com", "melbet.com",
    "mostbet.com", "parimatch.com", "22bet.com",
    "betwinner.com", "pin-up.bet", "leon.bet",
    // Poker
    "pokerstars.com", "partypoker.com", "ggpoker.com",
    "americascardroom.com", "blackchippoker.eu",
    "natural8.com", "wsop.com", "clubwpt.com",
    "globalpoker.com",
    // Online casinos
    "jackpotcitycasino.com", "royalvegascasino.com",
    "europacasino.com", "casinoeuro.com",
    "karamba.com", "playojo.com",
    "allbritishcasino.com", "casinogods.com",
    "guts.com", "dunder.com", "kaboo.com",
    "thrills.com", "superlenny.com", "nextcasino.com",
    "viks.com", "shadowbet.com", "ikibu.com",
    "codeta.com", "playfrank.com", "instacasino.com",
    "casinoheroes.com", "suomicasino.com",
    "coolcatcasino.com", "slotsofvegas.com",
    "slotsempire.com", "redstagcasino.com",
    "miamiclubcasino.com", "lincolncasino.eu",
    "libertyslots.eu", "everygame.eu",
    "dreamvegas.com",
    // Sweepstakes casinos and pick'em games
    "chumbacasino.com", "luckylandslots.com",
    "mcluck.com", "pulsz.com", "wowvegas.com",
    "fortunecoins.com", "sportzino.com", "modo.us",
    "crowncoins.com", "high5casino.com",
    "dingdingding.com", "prizepicks.com",
    "underdogfantasy.com",
    // Racing, lotteries, bingo, prediction markets
    "twinspires.com", "tvg.com", "xpressbet.com",
    "nyrabets.com", "powerball.com",
    "megamillions.com", "national-lottery.co.uk",
    "thelotter.com", "lottoland.com", "jackpot.com",
    "foxybingo.co.uk", "galabingo.com",
    "tombola.co.uk", "meccabingo.com", "buzzbingo.com",
    "polymarket.com",
]

// A host is held by a list when it is a listed
// domain or sits under one: the walk tries the whole
// host, then drops the first label and tries again,
// down to the bare domain.
func tbShieldMatch(host: String, in domains: Set<String>) -> Bool {
    var candidate = host
    while true {
        if domains.contains(candidate) { return true }
        guard let dot = candidate.firstIndex(of: ".") else { return false }
        candidate = String(candidate[candidate.index(after: dot)...])
    }
}

// Why a host is refused, if it is. The family filter
// is asked first — the stronger refusal wins the
// wording of the block page.
func tbShieldCategory(host: String?) -> TBShieldCategory? {
    guard let host = host?.lowercased(), !host.isEmpty else { return nil }
    if tbShieldMatch(host: host, in: TBShieldFamilyDomains) { return .family }
    if tbShieldMatch(host: host, in: TBShieldAdDomains) { return .advertising }
    return nil
}

func tbShieldCategory(urlString: String) -> TBShieldCategory? {
    return tbShieldCategory(host: URL(string: urlString)?.host)
}

// Escape a string for HTML — the block page prints
// the refused address, and an address is the reader's
// own typing, so it goes in as text, never as markup.
func tbShieldEscapeHTML(_ s: String) -> String {
    var out = s.replacingOccurrences(of: "&", with: "&amp;")
    out = out.replacingOccurrences(of: "<", with: "&lt;")
    out = out.replacingOccurrences(of: ">", with: "&gt;")
    out = out.replacingOccurrences(of: "\"", with: "&quot;")
    return out
}

// The block page: generated here, like the home page,
// in Chirpy's own voice. It says what was stopped and
// why, and it is honest about the way back — there is
// no script in this engine to walk history from a
// page, so the way back is the Back button the window
// already has, and the page says so.
func tbBlockedPageHTML(urlString: String, category: TBShieldCategory) -> String {
    let heading: String
    let why: String
    switch category {
    case .family:
        heading = "Stopped by the family filter"
        why = "This address is on the family filter's list — the adult "
            + "and gambling sites Chirpy will not open. The filter is on "
            + "on purpose, and there is no switch for it: that is the "
            + "promise on the home page, kept."
    case .advertising:
        heading = "Stopped by the ad shield"
        why = "This address belongs to an advertising and tracking "
            + "network — the kind of address other pages load quietly "
            + "behind a reader's back, not a place anyone goes on "
            + "purpose. The ad shield refused it."
    }
    return """
    <!DOCTYPE html>
    <html>
    <head><title>\(heading)</title></head>
    <body>
    <h1>Chirpy Browser</h1>
    <h2>\(heading)</h2>
    <p>Chirpy did not load <b>\(tbShieldEscapeHTML(urlString))</b>.</p>
    <p>\(why)</p>
    <p>Nothing was fetched from that address — the refusal happened
    here, on this Mac, before any request left it.</p>
    <p>Press the Back button above to return to the page you were on,
    or go <a href="chirpy://home">home</a>.</p>
    <h2>Thy word is a lamp to my feet</h2>
    <p>"Thy word is a lamp to my feet, and a light to my paths."
    &mdash; Psalm 118:105 (Douay-Rheims)</p>
    </body>
    </html>
    """
}

// The registrable domain of a host — its last two
// labels (example.com for www.example.com). An
// approximation, honestly: two-part public suffixes
// (co.uk and kin) read as the domain itself, which
// only ever makes two of their subdomains count as
// one site. It is the "same site" test the privacy
// dressing below is allowed to make.
func tbRegistrableDomain(_ host: String) -> String {
    let labels = host.lowercased().split(separator: ".")
    if labels.count <= 2 { return labels.joined(separator: ".") }
    return labels.suffix(2).joined(separator: ".")
}

// Privacy dressing for a subresource request — the
// fetches a page makes behind its reader's back.
// Against the page that asked (pageURLString):
//   same site — the request is left exactly as it
//     was built; today's behavior, untouched.
//   cross site — the request carries no cookies in
//     either direction (the session neither sends
//     stored cookies with it nor keeps any the reply
//     tries to set), and its Referer is the asking
//     page's origin only — scheme and host, never
//     the page's path.
// With no asking page to judge against, the request
// is left as built. Page loads themselves are not
// dressed here: they are the reader's own going,
// and Chirpy has never sent a Referer on one.
func tbShieldPrivacy(_ request: inout URLRequest, pageURLString: String?) {
    guard let pageURLString = pageURLString,
          let pageURL = URL(string: pageURLString),
          let pageHost = pageURL.host,
          let requestHost = request.url?.host else { return }
    if tbRegistrableDomain(pageHost) == tbRegistrableDomain(requestHost) {
        return
    }
    request.httpShouldHandleCookies = false
    if let scheme = pageURL.scheme {
        var origin = scheme + "://" + pageHost
        if let port = pageURL.port { origin += ":\(port)" }
        request.setValue(origin, forHTTPHeaderField: "Referer")
    }
}
