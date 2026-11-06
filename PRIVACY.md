# Политика конфиденциальности WatchGPT

Дата вступления в силу: 6 ноября 2026 г.

WatchGPT — приложение для Apple Watch, которое передаёт ваши вопросы ИИ-сервисам OpenAI (ChatGPT) и,
если вы включите этот режим, Anthropic (Claude). Здесь описано, какие данные обрабатывает приложение,
куда они уходят и как их удалить.

## Что собирает разработчик

Ничего. У WatchGPT нет собственного сервера, аналитики, рекламы, трекинга и сторонних SDK.
Разработчик не получает ваши вопросы, ответы, записи голоса, ключи или другие данные.

## Что хранится на часах

- чаты, созданные на часах, и их черновики;
- настройки, быстрые вопросы и история расхода лимитов;
- сохранённые места для умной стопки (координаты и радиус);
- журнал диагностики (последние ошибки, без текста вопросов);
- токен входа ChatGPT и API-ключи OpenAI и Anthropic — в Keychain часов.

Эти данные не покидают часы, кроме случаев ниже.

## Что передаётся сторонним ИИ-сервисам

Прежде чем что-либо отправить, приложение показывает экран согласия и ждёт вашего явного разрешения
отдельно для каждого сервиса.

**OpenAI (ChatGPT)** получает:
- текст ваших вопросов и предыдущие сообщения открытого чата;
- записи голоса, если для распознавания выбран ChatGPT или OpenAI API;
- токен входа в ваш аккаунт ChatGPT или ваш API-ключ OpenAI.

**Anthropic (Claude)**, только если вы добавили ключ и включили режим Claude, получает:
- текст ваших вопросов и предыдущие сообщения открытого чата;
- ваш API-ключ Anthropic.

Данные уходят напрямую с часов по HTTPS. Дальше их обрабатывают OpenAI и Anthropic по своим правилам:
- [Политика конфиденциальности OpenAI](https://openai.com/policies/privacy-policy)
- [Политика конфиденциальности Anthropic](https://www.anthropic.com/legal/privacy)

Эти компании обязаны обеспечивать защиту данных не ниже описанной здесь.

**Apple.** Если выбрано распознавание Apple, голос обрабатывает диктовка Apple по
[политике Apple](https://www.apple.com/legal/privacy/). Геопозиция запрашивается только когда вы
сохраняете место и остаётся на часах.

## Хранение и удаление

- Отозвать согласие: *Настройки → Конфиденциальность → Отозвать*. Сервис сразу отключается, токен
  или ключ удаляется с часов.
- Удалить всё: *Настройки → Конфиденциальность → Удалить все данные* или удалите приложение.
- Чаты в аккаунте ChatGPT хранит OpenAI: удалить их можно на [chatgpt.com](https://chatgpt.com) или
  запросом через [privacy.openai.com](https://privacy.openai.com). Данные API Anthropic — через
  [privacy.anthropic.com](https://privacy.anthropic.com).

## Дети

WatchGPT не предназначен для детей младше 13 лет и не собирает их данные сознательно.

## Изменения и контакты

О существенных изменениях политики приложение попросит согласие заново.
Вопросы, жалобы на ответы и запросы на удаление: [renothingg.github.io/?contact](https://renothingg.github.io/?contact).

---

# WatchGPT Privacy Policy (English)

Effective date: November 6, 2026.

**The developer collects nothing.** WatchGPT has no server, analytics, ads, tracking or third-party SDKs.

**On the watch:** chats, settings, saved places, a diagnostics log, and (in Keychain) your ChatGPT sign-in
token and OpenAI/Anthropic API keys.

**Shared with third-party AI, only after your explicit consent per service:** your questions, previous
messages of the open chat, voice recordings (if OpenAI/ChatGPT transcription is selected) and your
credentials are sent directly from the watch over HTTPS to OpenAI and, if you enable Claude mode, to
Anthropic. They process it under the
[OpenAI Privacy Policy](https://openai.com/policies/privacy-policy) and the
[Anthropic Privacy Policy](https://www.anthropic.com/legal/privacy).

**Control:** revoke consent or erase all data in *Settings → Privacy*, or delete the app. Data held by
OpenAI or Anthropic can be deleted through their own privacy portals.

**Contact:** [renothingg.github.io/?contact](https://renothingg.github.io/?contact).
