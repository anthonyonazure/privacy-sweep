# Thread: iPhone & Android

**1/ (hook + link)**
> "Just wipe the traces off my phone" doesn't work the way it does on a laptop, and the reason is good news for you.
>
> Full writeup + laptop scripts: github.com/anthonyonazure/privacy-sweep
>
> Here's what your phone keeps and how to clear each by hand:

**2/ Why there's no cleanup app for phones**
> iOS and Android wall every app off from every other one and encrypt the whole device with a key tied to your passcode. No app can read another app's data or reach the system history. That's why phones are hard to pull data off of, and why a "wipe traces" app can't exist on a stock phone.

**3/ iPhone: deleted photos & Safari**
> Photos > Albums > Recently Deleted > Select > Delete All (they sit there 30 days).
> Settings > Apps > Safari > Clear History and Website Data.

**4/ iPhone: location, Siri, keyboard**
> Settings > Privacy & Security > Location Services > System Services > Significant Locations > Clear History.
> Settings > Apps > Siri > Siri & Dictation History > Delete.
> Settings > General > Transfer or Reset > Reset > Reset Keyboard Dictionary.

**5/ Android: photos, browser, caches**
> Google Photos > Library > Trash > empty.
> Chrome > three dots > Delete browsing data > All time.
> Per app: Settings > Apps > (app) > Storage & cache > Clear cache.

**6/ Android: location & ad tracking**
> Google Maps > your photo > Your Timeline > settings > delete history.
> Settings > Privacy/Security > Ads > Delete advertising ID.

**7/ The one move that clears everything**
> Before selling or handing on the phone: factory reset (Erase All Content and Settings on iOS, Erase all data on Android). Because storage is encrypted, the reset throws away the key and makes the whole contents unrecoverable at once.

**8/ The everyday protection**
> A strong lock screen IS the encryption key. A 6+ digit PIN or a passphrase, with auto-lock on, protects every store above whenever the phone is locked. That's the real control.
> Laptop scripts + the detailed phone steps: github.com/anthonyonazure/privacy-sweep
