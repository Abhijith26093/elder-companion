Template name: `mitra_otp`

Category: `AUTHENTICATION`

Language: `en`

Suggested body:
`Your Mitra verification code is {{1}}. It expires in 5 minutes.`

Suggested button:
`Copy code`

Notes:
- Submit this template in your Meta WhatsApp Manager for the sender tied to `+919207037558`.
- After approval, set `WHATSAPP_TEMPLATE_NAME=mitra_otp` in `functions/.env`.
- The backend currently sends a single body variable: the OTP code.
