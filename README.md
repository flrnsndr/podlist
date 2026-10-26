<p align="center">
  <img src="docs/readme/header.svg" alt="Podlist: podcasts in playlists that fill themselves and remember where you left off" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-26-FF3B30?logo=apple&logoColor=white" alt="iOS 26">
  <img src="https://img.shields.io/badge/iPhone-SwiftUI-5856D6?logo=swift&logoColor=white" alt="SwiftUI for iPhone">
  <img src="https://img.shields.io/badge/data-stays_on_device-30B0C7" alt="Data stays on device">
  <img src="https://img.shields.io/badge/tracking-none-FF9500" alt="No tracking">
  <img src="https://img.shields.io/badge/languages-EN_·_DE-1C1C1E" alt="English and German">
</p>

<p align="center">
  <b>A podcast app for people who listen by topic.</b><br>
  Sort your shows into playlists, let new episodes file themselves,<br>
  and pick up every playlist exactly where you left it.
</p>

<p align="center">
  <a href="#why-podlist">Why</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#features">Features</a> ·
  <a href="#private-by-design">Privacy</a> ·
  <a href="#status">Status</a>
</p>

<p align="center">
  <img src="docs/readme/divider.svg" alt="" width="160">
</p>

## Why Podlist?

Most podcast apps give you **one queue**. Everything you subscribe to ends up in the same line: the morning news next to a three-hour history deep dive, last night's match analysis next to a course you are slowly working through. Sooner or later you stop using the queue and scroll through a long list of new episodes instead.

But that is not how most of us listen. In the morning you want the news, on a long drive something to sink into, after the weekend the sport. Your mood picks the **topic** first and the episode second.

Podlist is built around that idea:

- **Playlists are topics.** News, Sports, Knowledge, or whatever you come up with. A podcast can be in several of them, and new episodes land there on their own.
- **Every playlist remembers where you were.** Switch from *Sports* to *Knowledge* in the middle of an episode, come back a week later, and *Sports* continues exactly where you stopped.
- **One tap turns a playlist into your queue.** Start *News*, line up *Sports* after it, slip a single episode in between. Your playlists stay as they are, and every change can be undone.

Podlist is for you if you subscribe to more shows than fit into one queue, listen by mood or occasion, and want each topic to keep its place. And if you want all of that without an account, a cloud or analytics.

## How it works

<p align="center">
  <img src="docs/readme/how-it-works.svg" alt="New episodes are added to playlists automatically or wait in the inbox. Starting a playlist puts its episodes into the queue, from where you left off." width="100%">
</p>

**New episodes arrive** and go where you told them: to the top or the bottom of the podcast's playlists, or just into the **Inbox**, where you sort them with a swipe.

**Playlists keep their place.** A playlist is a list of episodes in the order you like. It knows which episode it plays next, no matter what else you listen to in between.

**The queue plays them.** Tap ▶ on a playlist and its episodes become your queue, starting where you left off. Line up another playlist after the current episode, add single episodes anywhere, drag things around. Switch playlists and the first one remembers where it stopped.

Two promises hold everywhere: **the queue never changes your playlists**, and **nothing you replace is gone**. The previous queue is one tap away.

## Screenshots

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/readme/screenshots/playlists.png" alt="Playlists tab: every playlist with its color, symbol and the episode it continues with"><br><sub><b>Playlists</b><br>Each one shows where it stands</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/start-menu.png" alt="Every playlist with its own play button; a long press offers Replace Queue, Play After Current Episode, Add to End of Queue"><br><sub><b>Start a playlist</b><br>Every playlist has its own ▶: tap to replace, long press for more</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/queue.png" alt="The queue in its own tab: the episode now playing and the episodes after it"><br><sub><b>Queue</b><br>Its own tab; one list, every episode once</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="docs/readme/screenshots/episode.png" alt="Episode details: play, add to the podcast's playlists, play next or last, the chapter list and show notes with timestamps"><br><sub><b>Episode details</b><br>Decide how to play, browse chapters</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/player.png" alt="Player with a progress bar split into chapters, the current chapter with its link, speed, sleep timer and the show notes below"><br><sub><b>Player</b><br>Chapters, speed, sleep timer</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/stats.png" alt="Listening stats for a month: listening time, listener type and overview"><br><sub><b>Listening stats</b><br>Month and year (sample data)</sub></td>
  </tr>
</table>

## Features

### 🗂️ Playlists

Every playlist has a color and a symbol, so you can tell them apart at a glance. Podlist starts you off with a few (News, Sports, Knowledge …), but they are yours: rename them, delete them, make new ones. When you subscribe to a podcast, Podlist suggests playlists based on its category, one tap and you are done.

- A podcast can be in **several playlists** at once.
- Sort by date, duration, title, by podcast, or by hand.
- **Played episodes** leave a playlist on their own, or stay if it is an archive or a course you want to keep in order.
- **Everything** is one more playlist with every episode of the others, newest first.

### 📥 Inbox

Every new episode from all your subscriptions lands in the Inbox, newest first, with a badge for what arrived since your last visit. Episodes that already went into a playlist show up as done. The rest you sort with a swipe: into the podcast's playlists, into another one, to the front of the queue, or out. Everything can be undone.

### ⏭️ Queue

The queue is one plain list of episodes, played from top to bottom, every episode in it only once. Tap ▶ on a playlist and its episodes replace the queue, from where you left off. Long press to line it up after the current episode or at the end instead. Single episodes go in with **Play next** or **Play last**, from anywhere in the app.

- The queue **never changes your playlists**. Each one keeps its order and remembers where it stopped.
- A replaced queue is not gone: an undo banner, a shake of your phone or **Previous queues** bring it back.

### 🎙️ Player

Playback speed and skipping intros and outros are set per podcast, once. The sleep timer stops after a set time, at the end of the chapter or at the end of the episode. Show notes with tappable timestamps sit right below the player, and the lock screen and your headphones can jump by seconds or by chapter.

### 📖 Chapters

Podlist takes chapters from wherever podcasters already put them: Podcasting 2.0 and Podlove chapters in the feed, ID3 and MP4 chapters inside the audio file, and timestamps in the show notes. The progress bar is split into chapters, chapter images replace the cover while the chapter plays (on the lock screen too), and chapter links open with a tap.

### ⬇️ Downloads

Download by hand or automatically per playlist, over Wi-Fi or cellular. Downloads of played episodes clean themselves up, and a storage overview shows what your podcasts take up, per podcast, with *delete all played* up front.

### 🔔 Background refresh & notifications

Feeds refresh in the background, so new episodes are there when you open the app. Notifications for new episodes can be switched on per podcast or per playlist, and you can add an episode to its playlists or to the queue right from the notification.

### 📊 Listening stats

A monthly and yearly look back at your listening, informative and a little cheeky: how much you listened and what that adds up to in everyday terms, your top podcasts, your longest streak, a heatmap of when you listen and what kind of listener that makes you (*commuter*, *night owl* …), how much time your playback speed saved and how often you fell asleep to which show. Share it as a story-format image. A listening history lists every episode you started, with the parts you heard. All of it is computed on your phone.

### 🚚 Moving in

Import your subscriptions via OPML from Pocket Casts, Overcast, Castro or any other app. Search the Apple Podcasts directory and ARD Sounds in one list, or paste a feed URL.

### 📱 At home on iOS

Podlist is written in Swift with SwiftUI and SwiftData, without third-party dependencies. Liquid Glass, Dark Mode, Dynamic Type and VoiceOver work the way you expect, color is never the only signal, and the app speaks English and German, following your device language.

## Private by design

**Everything runs locally, and all your data stays on your iPhone.**

- **No account, no sign-up.** Open the app and start listening.
- **No Podlist server.** Subscriptions, playlists, queue, listening positions and stats live in a database on your device and nowhere else.
- **No analytics, no tracking, no ads, no third-party SDKs.**
- The app talks to the network only for what it needs: feeds and audio come directly from each podcast's publisher, searches go to Apple's podcast directory and to ARD Sounds.

## Status

Podlist is a personal project in active development. It is not on the App Store (yet). The source is public to read; no license has been chosen, so all rights are reserved.

Ideas for later include optional iCloud sync, iPad and Mac, Apple Watch, CarPlay, widgets, Siri and Shortcuts, transcripts and OPML export.

### Building it yourself

You need **Xcode 26** and an iPhone or simulator running **iOS 26**. There are no dependencies to install: open `Podlist.xcodeproj`, select the `Podlist` scheme and an iOS 26 simulator, and run. No Apple account required.

A Debug build in the simulator starts with a made-up sample library (podcasts, playlists, a queue and a listening history), and its episodes play silence of the right length, so you can try everything offline. Your changes stay; delete the app in the simulator to start over.

**On your own iPhone**, signing needs your team: in the `Podlist` target under *Signing & Capabilities*, pick your team and change the bundle identifier (`com.podlistapp.podlist` belongs to the App Store version), for example to `com.yourname.podlist`. A free Apple account is enough. On a device the app starts empty.

The logic lives in the local package `PodlistKit` and has its own tests, which run on the Mac without a simulator: `cd PodlistKit && swift test`. The UI tests run with the test plan `Podlist` in Xcode.

<br>

<p align="center">
  <img src="docs/readme/divider.svg" alt="" width="160">
</p>

<p align="center">
  <img src="docs/readme/logo.svg" alt="Podlist app icon" width="72"><br>
  <sub><b>Podlist</b> · made for listening by topic · everything stays on your iPhone</sub>
</p>
