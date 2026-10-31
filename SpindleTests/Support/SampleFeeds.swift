import Foundation

/// Sample podcast feeds shared by the feed, library and refresh tests.
enum SampleFeeds {
    private static let namespaces = """
    xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" \
    xmlns:podcast="https://podcastindex.org/namespace/1.0" \
    xmlns:psc="http://podlove.org/simple-chapters"
    """

    private static let longQuietChannel = """
    <title>The Long Quiet</title>
    <description>Slow stories about empty places.</description>
    <itunes:author>Field Studio</itunes:author>
    <itunes:image href="https://example.com/art.jpg"/>
    """

    private static let ep112 = """
    <item>
      <title><![CDATA[Ep. 112 — Rooms & Rooms]]></title>
      <guid>lq-112</guid>
      <pubDate>Thu, 29 Oct 2026 08:00:00 +0000</pubDate>
      <itunes:duration>52:00</itunes:duration>
      <enclosure url="https://example.com/112.mp3" length="1000" type="audio/mpeg"/>
      <podcast:chapters url="https://example.com/112-chapters.json" type="application/json+chapters"/>
    </item>
    """

    private static let ep111 = """
    <item>
      <title>Ep. 111 — The Attic</title>
      <guid>lq-111</guid>
      <pubDate>Thu, 22 Oct 2026 08:00:00 +0000</pubDate>
      <itunes:duration>3600</itunes:duration>
      <enclosure url="https://example.com/111.mp3" length="1000" type="audio/mpeg"/>
    </item>
    """

    private static let ep113 = """
    <item>
      <title>Ep. 113 — Night Shift</title>
      <guid>lq-113</guid>
      <pubDate>Thu, 05 Nov 2026 08:00:00 +0000</pubDate>
      <itunes:duration>45:00</itunes:duration>
      <enclosure url="https://example.com/113.mp3" length="1000" type="audio/mpeg"/>
    </item>
    """

    private static func feed(channel: String, items: [String]) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" \(namespaces)>
        <channel>
        \(channel)
        \(items.joined(separator: "\n"))
        </channel>
        </rss>
        """
    }

    static let longQuiet = feed(channel: longQuietChannel, items: [ep112, ep111])

    static let longQuietThreeItems = feed(channel: longQuietChannel, items: [ep113, ep112, ep111])

    static let withPSC = feed(channel: "<title>Chaptered</title>", items: ["""
    <item>
      <title>With chapters</title>
      <guid>psc-1</guid>
      <enclosure url="https://example.com/psc.mp3" type="audio/mpeg"/>
      <psc:chapters version="1.2">
        <psc:chapter start="00:00:00" title="Intro"/>
        <psc:chapter start="12:30.5" title="Basement tapes"/>
      </psc:chapters>
    </item>
    """])

    static let noGuid = feed(channel: "<title>No Guid</title>", items: ["""
    <item>
      <title>Nine</title>
      <enclosure url="https://example.com/9.mp3" type="audio/mpeg"/>
    </item>
    """])

    static let oneWithoutEnclosure = feed(channel: "<title>Mixed</title>", items: ["""
    <item>
      <title>Text only</title>
      <guid>t-1</guid>
    </item>
    """, """
    <item>
      <title>With audio</title>
      <guid>t-2</guid>
      <enclosure url="https://example.com/t2.mp3" type="audio/mpeg"/>
    </item>
    """])
}
