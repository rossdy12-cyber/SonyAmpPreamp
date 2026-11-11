========================================================================
  STARK APP STORE // DESKTOP CODEMAGIC M2 IPA BUILDER (WORKS ON ANY PC)
========================================================================

HOW TO BUILD & SIGN AN IPA FROM RUNNABLE (OR ANY SWIFT PROJECT):

OPTION A: DROP A ZIP OR FOLDER + DOUBLE-CLICK
  1. Download the .zip file (or project folder) from Runnable and drop it
     into the "Drop_App_Here" folder (or edit any existing app folder here,
     like "nocturne", "lumen", "prism", "kith", "Nightfall", "CarbPrep").
  2. Double-click:
       1_Push_and_Build_IPA.bat
  3. It automatically:
     - Unpacks any .zip file into its app folder
     - Generates build-and-publish.sh + adds the workflow to codemagic.yaml
       if it is a brand-new app
     - Commits & pushes to https://navidrome.nas-server.co.uk/sidestore/SonyAmpPreamp.git
     - Fires the Codemagic M2 Xcode 16 build (which compiles the native arm64
       binary, uploads the IPA to TrueNAS, signs it with your 365-day Apple
       Developer certificate + provisioning profile, and publishes it to
       https://navidrome.nas-server.co.uk/sidestore/)

OPTION B: HANDS-FREE AUTO-WATCHER
  1. Double-click:
       3_Auto_Watch_Drop_Folder.bat
  2. Leave that window open. Whenever you save or drop a .zip or folder into
     "Drop_App_Here", it automatically pushes to Codemagic M2 and builds the IPA!

HOW TO PUT THIS ON YOUR SECOND PC:
  - Download https://navidrome.nas-server.co.uk/sidestore/Stark_IPA_Builder_Kit.zip
    onto the Desktop of your other PC, extract it, and double-click
    "2_Sync_Latest_From_Server.bat" (or "1_Push_and_Build_IPA.bat").
  - Works even if the other PC doesn't have Git installed (falls back to
    TrueNAS HTTPS Git-Commit API automatically).
========================================================================
