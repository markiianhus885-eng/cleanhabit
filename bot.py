import telebot
import requests

TELEGRAM_TOKEN = "8405984947:AAFqJ6L_Hyba3MgPDVwmcVX7ggExv5lSCfI"
GEMINI_KEY = "AQ.Ab8RN6JIvygpHZsLDNIOoO1TpKHgNVmAMGWWFPSgd9Y1X4nD3w"

bot = telebot.TeleBot(TELEGRAM_TOKEN)

def ask_gemini(text):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key={GEMINI_KEY}"
    data = {"contents": [{"parts": [{"text": text}]}]}
    r = requests.post(url, json=data)
    j = r.json()
    if "candidates" not in j:
        return f"Błąd Gemini: {j}"
    return j["candidates"][0]["content"]["parts"][0]["text"]

@bot.message_handler(func=lambda m: True)
def handle(message):
    try:
        response = ask_gemini(message.text)
        bot.reply_to(message, response)
    except Exception as e:
        bot.reply_to(message, f"Błąd: {e}")

bot.polling(non_stop=True)
