<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/hero-dark.png">
    <img src="docs/readme/hero-light.png" alt="The Podlist logo above an iPhone with four columns of colored tiles, one per playlist" width="100%">
  </picture>
</p>

<p align="center"><sub><b>PODCASTS FOR POWER USERS</b></sub></p>

<h1 align="center">A podcast app with playlists by topic.</h1>

<p align="center">
  Podlist is for people with lots of subscriptions.<br>
  Every podcast belongs to one or more playlists, and you listen to the one that fits right now.
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6822713541">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/readme/app-store-white.svg">
      <img src="docs/readme/app-store-black.svg" alt="Download on the App Store" height="48">
    </picture>
  </a>
</p>

<p align="center">
  Free · iPhone · iOS 26 · English and German · No account<br>
  <a href="https://podlistapp.com/en/">podlistapp.com</a>
</p>

## One list for everything, or one playlist per topic.

In most apps, every new episode lands in the same queue. In Podlist, it lands in different playlists.

<table>
  <tr>
    <th>One list for everything</th>
    <th>One playlist per topic</th>
  </tr>
  <tr>
    <td valign="top">
      The Day in 15: Monday<br>
      Lab Radio 41: Cold, Part 2<br>
      Episode 86: The Mountain Guide<br>
      Extra Time after the Derby<br>
      The Day in 15: Tuesday<br>
      Why Bridges Sway<br>
      Coffee Break 212<br>
      Lab Radio 40: Cold, Part 1<br>
      The World Tonight
    </td>
    <td valign="top">
      <b>News</b> · The Day in 15: Monday · The Day in 15: Tuesday · The World Tonight<br><br>
      <b>Science</b> · Lab Radio 40: Cold, Part 1 · Lab Radio 41: Cold, Part 2 · Why Bridges Sway<br><br>
      <b>Interviews</b> · Episode 86: The Mountain Guide<br><br>
      <b>Light</b> · Extra Time after the Derby · Coffee Break 212
    </td>
  </tr>
</table>

## Some podcasts belong in two or more playlists.

So you assign them to several, and one tap puts each new episode into all of them.

1. **You assign the podcast to two playlists.** *The Long Conversation* goes into *Interviews* and *Science*.
2. **A new episode waits in the inbox.** *Episode 87: The Astronaut*, with the button *Add to Interviews and Science*.
3. **One tap puts it into both.** Each playlist picks up at its own place: *Interviews* continues with episode 86, *Science* with *Why Bridges Sway*.

## This is how it looks in the app.

<table>
  <tr>
    <td align="center" valign="top" width="33%"><img src="docs/readme/screenshots/playlists.png" width="240" alt="The Playlists tab: Everything and the topic playlists, each with a play button and “Playing”, “Continue” or “Next”"><br><sub><b>Playlists</b><br>Every playlist knows its place: “Playing”, “Continue” or “Next”. Tap ▶ to start one, touch and hold for Play After Current Episode or Play Last.</sub></td>
    <td align="center" valign="top" width="33%"><img src="docs/readme/screenshots/inbox.png" width="240" alt="Inbox with playlist filters, new episodes with buttons like “Add to Politics and Business” and “Dismiss Rest”"><br><sub><b>Inbox</b><br>Filter by playlist. One tap puts an episode into every playlist of its podcast; Dismiss Rest clears what is left.</sub></td>
    <td align="center" valign="top" width="33%"><img src="docs/readme/screenshots/queue.png" width="240" alt="Queue: the playing episode, a single episode and the episodes of the started Sports playlist"><br><sub><b>Queue</b><br>The playing episode, single episodes and a started playlist. Drag to reorder.</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top" width="33%"><img src="docs/readme/screenshots/sort.png" width="240" alt="A playlist's menu: sort manually, by release date, date added, title, duration or podcast"><br><sub><b>Sorting</b><br>Per playlist by date, duration, title, podcast or by hand.</sub></td>
    <td align="center" valign="top" width="33%"><img src="docs/readme/screenshots/stats.png" width="240" alt="Listening stats: top podcasts, time per playlist, the longest session"><br><sub><b>Listening stats</b><br>Month and year, computed on your iPhone (sample data).</sub></td>
    <td></td>
  </tr>
</table>

**Everything** is one more playlist with every episode from all the others, newest first. You choose which playlists it includes.

## Free, no account, no data sent anywhere.

**Free.** No in-app purchases, no subscription, no ads. That won’t change.

**No account · No server · No tracking · No AI.** Everything stays on your iPhone. The app goes online only for feeds and audio, which come straight from each podcast’s publisher, and for searches in Apple’s podcast directory and ARD Sounds.

## Already using a podcast app?

Export your subscriptions as an OPML file and import it into Podlist. If a podcast can’t be added, Podlist tells you why. You can also search Apple Podcasts and ARD Sounds in one list, or add a feed by URL.

## What else Podlist does.

Sort by date, duration, title, podcast or by hand · “Everything”: every episode from all playlists · Listening stats · Listening history · Chapters from five sources · Speed per podcast · Skip intros and outros · Downloads per playlist · Notifications per podcast · Hide playlists · Undo

## FAQ

**Why not Apple Podcasts or Overcast?**<br>
Both are good apps, and if one queue works for you, you don’t need Podlist. Podlist is for lots of subscriptions listened to by topic: every podcast belongs to fixed playlists, new episodes only go there, and each playlist picks up at its own place.

**Is my data synced between devices?**<br>
No. Podlist stores everything on your iPhone and has no server to sync through.

**What can’t Podlist do?**<br>
Podlist runs only on iPhone with iOS 26 or later. There is currently no version for iPad, Mac, Apple Watch or CarPlay, and nothing is synced between devices.

**How do I find new podcasts?**<br>
With the search in the app. To browse by topic, try free podcast directories such as [Listen Notes](https://www.listennotes.com), [Podcast Index](https://podcastindex.org), [Podchaser](https://www.podchaser.com) or [fyyd](https://fyyd.de). Whatever you find there, search for it by name in Podlist or add it by feed URL.

**Will Podlist stay free?**<br>
Yes. There are no in-app purchases, no subscription and no ads, and that won’t change.

**Who’s behind it?**<br>
Podlist is a private project. It exists because no podcast app for iPhone fit more than 150 subscriptions listened to by topic and mood.

## The source

The source is public to read; no license has been chosen, so all rights are reserved. Podlist is written in Swift with SwiftUI and SwiftData, without third-party dependencies.

**Building it yourself.** You need **Xcode 26** and an iPhone or simulator running **iOS 26**. There is nothing to install: open `Podlist.xcodeproj`, select the `Podlist` scheme and an iOS 26 simulator, and run. No Apple account required.

A Debug build in the simulator starts with a made-up sample library (podcasts, playlists, a queue and a listening history), and its episodes play silence of the right length, so you can try everything offline. Your changes stay; delete the app in the simulator to start over.

**On your own iPhone**, signing needs your team: in the `Podlist` target under *Signing & Capabilities*, pick your team and change the bundle identifier (`com.podlistapp.podlist` belongs to the App Store version), for example to `com.yourname.podlist`. A free Apple account is enough. On a device the app starts empty.

The logic lives in the local package `PodlistKit` and has its own tests, which run on the Mac without a simulator: `cd PodlistKit && swift test`. The UI tests run with the test plan `Podlist` in Xcode.

<br>

<p align="center">
  <img src="docs/readme/logo.svg" alt="Podlist app icon" width="72"><br>
  <b>Podlist</b><br>
  <sub>Podcasts for Power Users. Free for iPhone on the <a href="https://apps.apple.com/app/id6822713541">App Store</a>.</sub>
</p>
