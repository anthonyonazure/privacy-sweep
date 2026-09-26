# Thread: iPhone

**1/ (hook + link)**
> "Just wipe the traces off my iPhone" doesn't work the way it does on a laptop, and the reason is good news for you.
>
> Full writeup + laptop scripts: github.com/anthonyonazure/privacy-sweep
>
> What your iPhone keeps and how to clear each by hand:

**2/ Why there's no cleanup app for iPhone**
> iOS walls every app off from every other one and encrypts the whole device with a key tied to your passcode. No app can read another app's data or reach the system history. That's why iPhones are hard to pull data off of, and why a "wipe traces" app can't exist on a stock phone.

**3/ Deleted photos**
> They don't leave right away. Photos > Albums > Recently Deleted > Select > Delete All. They sit there 30 days otherwise.

**4/ Safari history, cookies and cache**
> A quick "clear history" can miss cached site data.
> Settings > Apps > Safari > Clear History and Website Data clears all three at once.

**5/ Where you've been**
> iOS keeps a private log of places you frequent.
> Settings > Privacy & Security > Location Services > System Services > Significant Locations > Clear History.

**6/ Siri and keyboard memory**
> Settings > Apps > Siri > Siri & Dictation History > Delete.
> Settings > General > Transfer or Reset iPhone > Reset > Reset Keyboard Dictionary (clears learned words).

**7/ The one move that clears everything**
> Before selling or handing it on: Settings > General > Transfer or Reset iPhone > Erase All Content and Settings. Because storage is encrypted, this throws away the key and makes the whole contents unrecoverable at once.

**8/ The everyday protection**
> A strong passcode IS the encryption key. Settings > Face ID & Passcode > Change Passcode > Passcode Options > Custom Alphanumeric Code. With auto-lock on, that key protects every store above whenever the phone is locked.
> Laptop scripts + detail: github.com/anthonyonazure/privacy-sweep

---

**Scope note:** this is personal privacy hygiene for your own device, not a list of everywhere a forensic examiner looks, and not a way to defeat an investigation.
