# Shipping a Mac — pre-ship checklist and known failure modes

For whoever prepares the laptop (today: Dan). The scripts in this repo only run *after* the Mac
is enrolled and the employee can sign in; everything below is what has to be true before that,
and it is written from the failures of a real onboarding rather than from the ideal path.

---

## 1. Never power on the Mac before it appears in Apple Business

**This is the one that costs a whole afternoon.** A Mac that reaches Setup Assistant while it is
not yet in Apple Business caches an "unmanaged" activation record. From then on it will *silently
skip* the Remote Management pane on later boots — no error, no prompt, just a normal consumer
setup, and no MDM.

- Read the serial off the **box**, not off a booted Mac.
- Confirm the device is in Apple Business first (§2), *then* power it on.
- If it has already been powered on unenrolled, don't panic — go to §4, and expect to erase it.

## 2. Verify in Apple Business before the Mac is powered on

Everything here is checked in Apple Business, per device and per person:

- [ ] Device appears in **Inventory**.
- [ ] Device's **Management Service** is set to **Built-in device management**.
- [ ] Device (or the user it's assigned to) is in the **Work Devices Blueprint**.
- [ ] Employee exists in **People**.
- [ ] Employee is added to that **Blueprint's People**.
- [ ] **Create Sign-In has been run for the employee.**
- [ ] **Microsoft 365 assigned as a Managed App** to the device or user.

Microsoft 365 is delivered **by Apple Business Managed Apps first** — that's the path that needs
no password from the employee. The `microsoft-office` cask in `user.sh` and the deferred-install
mechanics behind it stay exactly as they are, as the fallback for a Mac the Managed App hasn't
reached; if ABM has already installed it, the cask sees it and simply records it as present.

The Create Sign-In box is not optional today. Until Apple ↔ Entra federation is connected, a Managed Apple
Account created by directory sync has **no password at all**, and the employee simply cannot sign
in — this was the second failure of the live run. Running Create Sign-In is what gives them
credentials. Once federation is connected, this step goes away.

## 3. Strongly recommended: test-enroll, then erase

While the Mac is still in your hands:

1. Boot it and take it through enrollment far enough to see the **Remote Management** pane.
2. Then **System Settings → General → Transfer or Reset → Erase All Content and Settings**.

This proves the ADE record is actually live *before* the employee has it, and the erase refreshes
the activation record so their first boot is clean. It costs ten minutes and removes the entire
class of problems in §1.

## 4. Recovery ladder — the Remote Management pane didn't appear

Work down this list; each step is cheap and the earlier ones often suffice.

1. **Power-cycle once at the pane.** A single restart at Setup Assistant frequently pulls the
   record down.
2. **Already clicked through to the desktop?** Don't erase yet — open **System Settings and sign
   in with the Managed Apple Account**. That triggers enrollment. (This is what worked on the
   live run.)
3. **CLI fallback:** `sudo profiles renew -type enrollment`, then approve the **Allow** prompt.
4. **"Failed to request configuration from the cloud"** while the Apple Business config is
   demonstrably correct means Apple-side propagation, not a mistake on our end. Wait **30–60
   minutes between retries** rather than hammering it.
5. **Still stuck:** Apple Business support, **1-866-902-7144**, with the device **serial** and the
   **Organization ID** to hand.

### After any of those: check *which kind* of enrollment you got

```
profiles status -type enrollment
```

The Setup Assistant Remote Management pane is the **only** path that produces a locked Automated
Device Enrollment. Expect:

```
Enrolled via DEP: Yes
MDM enrollment: Yes
```

The System Settings sign-in route (step 2) works, but it yields **User-Approved MDM, not DEP** —
confirmed on the live machine, which reported `Enrolled via DEP: No` / `MDM enrollment: Yes (User
Approved)`. That difference matters: a User-Approved enrollment is **not locked**, so the employee
can remove management themselves, and Apple may not fire the enrollment-time package installs.

So: the recovery route is fine for *getting someone working today*, but it is not the end state.
Once Apple-side propagation has settled, prefer **erase and redo through the Remote Management
pane** to land a proper DEP enrollment, and check with the command above after any future first
boot rather than assuming.

## 5. Pre-arrival phone step — do this before the laptop

The employee needs their phone set up before they ever open the Mac, because day 1 asks for a Duo
push in its very first step:

- [ ] Send the **temporary access pass (TAP)**; the employee signs in at **aka.ms/mysecurityinfo**
      and sets their password.
- [ ] Send the **Duo activation link** from the Duo Admin Panel, and confirm the employee has
      activated **Duo Mobile** on their phone.

Directory sync creating the Duo user is **not** activation, and there is **no inline enrollment**
during the Microsoft sign-in — if this step is skipped, the employee hits step 1 of `benex-day1`
with no way to approve the push, and the whole day-1 flow stalls behind it.

---

## Then hand it over

The employee opens Terminal and runs the one-liner from the [README](./README.md); when it
finishes, `benex-day1` walks them through the sign-ins. On a Mac provisioned by the signed
package rather than the one-liner, Microsoft 365 is *deferred* rather than installed — its
installer needs an admin password and nobody is at the keyboard at first login — so expect
`benex-day1` to install it, with a password prompt, as its first real step. Their mailbox is the first thing they
reach, which is why §5 has to be done first.
