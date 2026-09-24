# NoteNarrator

We built NoteNarrator for students who want to review a lecture without sending their files to a website. Import a file, then study from its summary, notes, quiz, and flashcards. Notes and quiz questions point back to a page, slide, or part of a recording when that reference is available.

## Run the app

Open `NoteNarrator.xcodeproj` in Xcode 27, select the NoteNarrator scheme, and press Run. Xcode will fetch the ZIPFoundation package used to read Word and PowerPoint files.

The app targets macOS 26.5 or later. Study-material generation needs a Mac with Apple Intelligence enabled and its on-device model ready. The app shows the model's status before you import. There is no NoteNarrator account or subscription.

## What you can import

- PDF, PowerPoint (`.pptx`), Word (`.docx`), and plain text
- Audio recordings such as MP3, WAV, M4A, and AIFF
- MP4 and MOV videos

Files are read on the Mac. For a video, NoteNarrator combines its speech transcript with words read from selected frames. It does not understand every photo or diagram. If a slide or frame has no readable text, the picture may still appear in Notes, but the generated explanation may miss what it shows.

Large files can produce incomplete results. When the model cannot process a section, Notes shows the original extracted text under **SOURCE TEXT — AI notes unavailable**, and the app keeps a warning. That text is not an AI summary; check the original file before relying on it. Retry can recover some sections without replacing the work already saved.

## Where the code is

- `NoteNarrator/Services/Extraction/` reads documents, audio, and video.
- `NoteNarrator/Services/Generation/` splits source text and builds study material with Apple's on-device model.
- `NoteNarrator/Models/` stores lectures, notes, questions, cards, figures, and bookmarks with SwiftData.
- `NoteNarrator/Views/` contains the macOS interface.

This is our Senior Project 1 app. We are still testing it with real lecture files, so please report a wrong answer or missing source reference rather than assuming generated content is correct.
