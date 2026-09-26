# Thread: Android

**1/ (hook + link)**
> "Just wipe the traces off my phone" doesn't work the way it does on a laptop, and the reason is good news for you.
>
> Full writeup + laptop scripts: github.com/anthonyonazure/privacy-sweep
>
> What your Android keeps and how to clear each by hand:

**2/ Why there's no cleanup app for Android**
> Android walls every app off from every other one and, on modern versions, encrypts storage with a key tied to your lock screen. No normal app can read another app's data or the protected databases. That's why a "wipe traces" app can't do much on a stock, non-rooted phone.

**3/ Deleted photos**
> Google Photos > Library > Trash > empty. Deleted shots sit there for up to 60 days otherwise.

**4/ Browser history, cookies and cache**
> Chrome > three dots > Delete browsing data > set Time range to All time > tick all types > clear. Same idea in any other browser you use.

**5/ Per-app caches**
> Apps stockpile thumbnails and downloaded content.
> Settings > Apps > (app) > Storage & cache > Clear cache. Do it for the chatty ones (gallery, social, maps).

**6/ Where you've been, and ad tracking**
> Google Maps > your profile photo > Your Timeline > settings > delete history.
> Settings > Privacy or Security > Ads > Delete advertising ID (stops cross-app tracking).

**7/ The one move that clears everything**
> Before selling or handing it on: Settings > System > Reset options > Erase all data (factory reset). Because storage is encrypted, this throws away the key and makes the whole contents unrecoverable at once.

**8/ The everyday protection**
> A strong lock screen IS the encryption key. Set a 6+ digit PIN or a passphrase (Settings > Security > Screen lock). With auto-lock on, that key protects every store above whenever the phone is locked.
> Laptop scripts + detail: github.com/anthonyonazure/privacy-sweep

---

**Scope note:** this is personal privacy hygiene for your own device, not a list of everywhere a forensic examiner looks, and not a way to defeat an investigation.
