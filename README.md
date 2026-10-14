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
  Sort your shows into themed playlists, let new episodes file themselves,<br>
  and pick up every playlist exactly where you left it.
</p>

<p align="center">
  <a href="#why-podlist">Why</a> ·
  <a href="#who-its-for">Who it's for</a> ·
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

Most podcast apps give you **one queue**. Everything you subscribe to ends up in the same line: the morning news next to a three-hour history deep dive, last night's match analysis next to a course you are working through slowly. You end up rearranging the queue by hand, or you stop using it and scroll through a long list of new episodes instead.

But that is not how most of us listen. In the morning you want the news. On a long drive, something to sink into. After the weekend, sport. Your mood picks the **topic** first and the episode second.

Podlist is built around that idea:

- **Playlists are topics.** News, Sports, Knowledge, or whatever you make up. Each podcast belongs to one or more of them, and new episodes land there on their own.
- **Every playlist remembers where you were.** Switch from *Sports* to *Knowledge* in the middle of an episode, come back days later, and *Sports* continues exactly where you stopped.
- **The queue holds whole playlists, not just episodes.** Queue *News* and then *Sports*, slip a single episode in between, replace everything on a whim. Nothing gets lost: every change can be undone.

## Who it's for

Podlist is for you if …

- 🎧 **you subscribe to more than a handful of shows** and your single queue has turned into a to-do list.
- 🗂️ **you listen by mood or occasion**: news while making coffee, long conversations on the train, sport after the weekend.
- ⏯️ **you jump back and forth** between topics and want each one to keep its place.
- 📚 **you work through archives or courses** and want a playlist that keeps everything, in order, played or not.
- 🔒 **you care about privacy** and want an app without an account, a cloud backend or analytics.
- 🔀 **you are coming from Pocket Casts, Overcast or Castro** and want to bring your subscriptions along in a minute.

## How it works

<p align="center">
  <img src="docs/readme/how-it-works.svg" alt="New episodes are added to playlists automatically or wait in the inbox. Playlists are started as blocks in the queue and continue where you left off." width="100%">
</p>

1. **New episodes arrive.** Each podcast is assigned to one or more playlists. For every assignment you decide whether new episodes are added at the top, at the bottom, or not at all. Every new episode also shows up in the **Inbox**, so you can sort the rest with a swipe.
2. **Playlists fill up and keep their place.** A playlist is a list of real episodes, sorted the way you like. It knows which episode it is playing or plays next, independent of everything else.
3. **The queue plays them.** Tap ▶ on a playlist and it becomes your queue. Add single episodes before or after it, or line up several playlists one after another. A playlist block stays live: new episodes flow straight in.

Two promises hold everywhere: **The queue never changes your playlists**, and **nothing you replace is gone**. The previous queue is one tap away.

## Screenshots

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/readme/screenshots/playlists.png" alt="Playlists tab: every playlist with its color, symbol and the episode it continues with"><br><sub><b>Playlists</b><br>Each one shows where it stands</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/start-menu.png" alt="Every playlist with its own play button; a long press offers Replace Queue, Play After Current Episode, Add to End of Queue"><br><sub><b>Start a playlist</b><br>Every playlist has its own ▶: tap to replace, long press for more</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/queue.png" alt="The queue in its own tab, with the News and Technology playlists as blocks"><br><sub><b>Queue</b><br>Its own tab; whole playlists as blocks</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="docs/readme/screenshots/episode.png" alt="Episode details with play options, playlists and a chapter list with links"><br><sub><b>Episode details</b><br>Decide how to play, browse chapters</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/player.png" alt="Player showing the current chapter, chapter marks on the progress bar, speed and sleep timer"><br><sub><b>Player</b><br>Chapters, speed, sleep timer</sub></td>
    <td align="center" width="33%"><img src="docs/readme/screenshots/stats.png" alt="Listening stats for a month: listening time, listener type and overview"><br><sub><b>Listening stats</b><br>Month and year (sample data)</sub></td>
  </tr>
</table>

## Features

### 🗂️ Playlists

- Six starter playlists (**News, Politics, Sports, Entertainment, Knowledge, Technology**), each with its own color and symbol. Rename them, delete them, or create your own.
- A podcast can live in several playlists at once.
- When you subscribe, Podlist suggests playlists based on the podcast's category. One tap and you are done, or skip it.
- Sort by release date, duration, date added, title, by podcast (grouped) or manually by drag and drop.
- Decide per playlist what happens to played episodes: **remove** them automatically, or **keep** them, which is perfect for archives and courses you want to replay.
- Each playlist shows where it stands: *Now playing*, *Resumes at* or *Next*.

### 📥 Inbox

- Every new episode from all your subscriptions, newest first, with a badge for what arrived since your last visit.
- Episodes that were already auto-added appear as done, together with the playlists they landed in, so you can still add them somewhere else.
- Swipe to **add** to the podcast's playlists, **add to playlist …**, **play next** or **discard**, each with undo. Or add everything at once.
- Filter by playlist, or show only episodes from podcasts without a playlist.

### ⏭️ Queue

- A queue of **single episodes and whole playlists**.
- Tap ▶ on a playlist to play it right away. Long press for more: **Replace**, **After the current episode** or **At the end**. Prefer to be asked every time? There is a setting for that.
- **Play next** and **Play last** for single episodes, from anywhere.
- Skip an episode and it moves right behind the one now playing, so you never lose it.
- Replaced or cleared queues go into **Previous queues**. An undo banner appears right away, and shaking your phone works too.
- Tapping an episode opens its details instead of starting playback. Decide there: play now, queue it, or start the playlist from this episode.

### 🎙️ Player

- **Playback speed** globally and per podcast.
- **Skip intros and outros** per podcast, set once and forget about it.
- Adjustable skip intervals; the buttons on the lock screen and your headphones can jump by seconds or by chapter.
- **Sleep timer**: after a set time, at the end of the chapter, or at the end of the episode.
- Lock screen, Control Center and headphone controls.
- Every episode remembers its position. Finished episodes start from the beginning next time.
- Show notes with tappable timestamps.

### 📖 Chapters

Podlist reads chapters from **everything podcasters already publish**, with no extra work on their side:

| Source | Where it comes from |
|---|---|
| Podcasting 2.0 JSON chapters | linked from the feed |
| Podlove Simple Chapters | inside the feed, very common in German-language podcasts |
| ID3 chapters | inside MP3 files |
| MP4 / M4A chapters | inside AAC files |
| Timestamps in show notes | "12:34 Topic" lines in the episode description |

Chapter images replace the cover while the chapter plays, on the lock screen too. Chapter links open with a tap, the progress bar is split into chapters, and you can jump from chapter to chapter.

### ⬇️ Downloads & storage

- Download by hand or **automatically per playlist**, over Wi-Fi or cellular. iOS Low Data Mode is respected.
- Downloads of played episodes are deleted automatically (you can turn that off).
- A **storage overview** shows how much space your podcasts take, broken down by podcast, with the most useful action up front: **delete all played**.
- Pause, resume and retry downloads, and keep an eye on free space.

### 🔔 Notifications & background refresh

- Feeds refresh in the background, so new episodes are there when you open the app.
- Notifications for new episodes, on or off per podcast.
- Act right from the notification: **Add to playlists**, **Play next** or **Play last**.

### 📊 Listening stats

A monthly and yearly look back at your listening, informative and a little cheeky:

- Total listening time, in real time and in episode time, plus what that adds up to in everyday terms.
- Your top podcasts, your favorite playlist and genre, your longest streak and your record day.
- A heatmap of when you listen, and what kind of listener that makes you: *commuter*, *night owl*, *weekend listener* …
- How much time your playback speed saved, how often you fell asleep to which show, the oldest episode you dug up, and the subscriptions you have been neglecting.
- Share a summary as a story-format image.

All of it is computed on your phone from a local listening log.

### 🚚 Moving in

- **Import your subscriptions via OPML** from Pocket Casts, Overcast, Castro and others. If a feed cannot be imported, Podlist tells you why.
- Search the Apple Podcasts directory, or paste any feed URL.

### 📱 At home on iOS

- Built with standard iOS components: Liquid Glass, Dark Mode, Dynamic Type and VoiceOver work the way you expect.
- Color is never the only signal: every playlist has a symbol, too.
- English and German, following your device language. Even the starter playlists are translated.

## Private by design

**Everything runs locally, and all your data stays on your iPhone.**

- **No account, no sign-up.** Open the app and start listening.
- **No Podlist server.** Your subscriptions, playlists, queue, listening positions and statistics live in a database on your device and nowhere else.
- **No analytics, no tracking, no ads, no third-party SDKs.**
- The app only talks to the network for what it needs: it loads feeds and audio **directly from each podcast's publisher**, and search queries go to Apple's podcast directory.
- Background refresh and new-episode notifications run on your phone, not on a push server.
- Your listening stats are computed on the device. They only leave it if you share the image yourself.

## Status

Podlist is a personal project in active development. It is not on the App Store (yet). The source is public to read; no license has been chosen, so all rights are reserved.

Ideas for later include optional iCloud sync, iPad and Mac, Apple Watch, CarPlay, widgets, Siri and Shortcuts, transcripts, skipping chapters automatically, and OPML export.

### Building it yourself

You need **Xcode 26** and an iPhone or simulator running **iOS 26**. There are no dependencies to install.

1. Open `Podlist.xcodeproj`.
2. Select the `Podlist` scheme and run.

To look around without subscribing to anything, add the launch argument `-uiTesting` to the scheme. The app then starts offline with sample podcasts, playlists and listening history (audio does not play in this mode).

<br>

<p align="center">
  <img src="docs/readme/divider.svg" alt="" width="160">
</p>

<p align="center">
  <img src="docs/readme/logo.svg" alt="Podlist app icon" width="72"><br>
  <sub><b>Podlist</b> · made for listening by topic · everything stays on your iPhone</sub>
</p>
