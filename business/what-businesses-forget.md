# What businesses forget

Each item is something an audit should list and a person should decide on. None of it is
cleared by privacy-sweep. Where a setting or length depends on your plan, look at your own
tenant or account ("check your tenant").

## Network and building

- **Guest and IoT networks.** Is there a separate network for visitors and for cameras,
  badge readers, thermostats, and smart screens? A flat network lets one weak device reach
  everything. Guest Wi-Fi passwords should change on a schedule and when staff leave.
- **Phones (VoIP).** Desk phones and the phone system keep call records, voicemail, and
  sometimes call recordings. Ask the provider what is kept and for how long (check your
  tenant). Voicemail-to-email copies your voicemail into mailboxes.
- **Point-of-sale systems.** Card terminals and registers keep transaction logs. Card data
  has its own strict rules, so do not clear or reset these without the processor's guidance.
- **Door badges and visitor logs.** They record who was where and when. Check who can read
  the badge system and how long entries are kept (check your tenant).
- **Cameras and recorders.** Check where footage is stored, who can view it, how long it is
  kept, and that the recorder has no default password.

## Accounts and cloud

- **Microsoft 365 and Google Workspace audit logs.** These show sign-ins, file access, and
  sharing. The length they are kept depends on your plan and settings (check your tenant).
  Turning them on is a decision to make before an incident, not after.
- **Former employees.** Their accounts, mailboxes, forwarding rules, shared files, saved
  devices, and phone enrollments should be closed or reassigned on the last day. Check for
  mail rules that forward to a personal address.
- **Admin and shared accounts.** List who holds admin rights. Shared logins hide who did what.
- **Sign-in rules.** Multi-factor sign-in on every account that can reach company data, with
  recovery methods reviewed.
- **Shadow IT.** Staff sign up for file-sharing, note, AI, and chat tools with work email.
  Look at the connected apps and sign-in logs for services nobody approved.

## Devices

- **Managed devices.** If you use a device-management tool (Intune, Jamf, or similar), check
  what it reports, what it can wipe remotely, and whether lost-device wipe is turned on.
- **Unmanaged and personal devices.** Decide whether they may reach company mail and files.
- **Retired and returned equipment.** Laptops, phones, copiers, and network storage need a
  tracked wipe or destruction step. See the household retiring-devices page.
- **Backups.** Backups are copies too. Know where they live and how long they are kept, and
  remember that deleting live data does not delete the backup.

## Records you may be required to keep

Before any clean-up, list what the business is required to keep (patient, tax, payroll,
contract, safety, and security records) and for how long (check with counsel or your
compliance owner). Clear only what falls outside that list.
