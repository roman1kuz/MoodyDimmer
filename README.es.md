# Moody Dimmer

[English](README.md) · [Русский](README.ru.md) · **Español**

_**M**y **O**ccasionally **O**dd **D**immer **Y**ields **D**arkness, **I**f **M**acOS **M**ostly **E**xecutes **R**equests._

Una app de la barra de menús de macOS que oscurece, desenfoca o añade grano de película a todo menos a la ventana
activa.

- Oscurecer, desenfoque o ambos, con grano opcional, cada uno con su propia intensidad.
- Mantiene iluminada la ventana activa o todas las ventanas de la app activa.
- Transiciones suaves al cambiar el foco; el fondo nunca parpadea.
- Se aparta a pantalla completa, en Mission Control, en Mostrar escritorio y al arrastrar archivos a otra app.
- Activación rápida con un atajo de teclado (⌃⌥⌘D) o agitando el puntero.
- En reposo casi no cuesta nada: funciona por eventos, sin temporizadores de sondeo.
- Inglés, ruso y español.

## Instalación

Requiere macOS 14 o posterior (desarrollada y probada en macOS 27).

- **Homebrew:** `brew install --cask roman1kuz/tap/moody-dimmer`; para actualizar, `brew upgrade moody-dimmer`.
- **Descarga:** el DMG desde [Releases](https://github.com/roman1kuz/MoodyDimmer/releases/latest);
  arrastra la app a Aplicaciones.

Moody Dimmer no está notarizada por Apple (eso requiere una cuenta de desarrollador de pago), así que macOS bloquea su
primer arranque, y el primero después de cada actualización. Para abrirla, ve a *Ajustes del Sistema → Privacidad y
seguridad* y haz clic en *Abrir igualmente*. El acceso de Accesibilidad se mantiene entre actualizaciones.

### Compilar desde el código

Necesita las Command Line Tools de Xcode (`xcode-select --install`). Una compilación propia se abre sin el aviso.

```sh
git clone https://github.com/roman1kuz/MoodyDimmer.git && cd MoodyDimmer
./scripts/make-cert.sh             # una vez: certificado local de firma de código
./scripts/build-app.sh --install   # compilar, copiar a /Applications y abrir
```

La compilación también crea un DMG en `build/`. Detalles: [docs/building.es.md](docs/building.es.md).

## Permisos

- **Accesibilidad**: necesaria para seguir las ventanas dentro de una misma app (diálogos, segundas ventanas, ventanas
  que se mueven). Sin ella, el efecto solo sigue los cambios entre apps. Mientras no se conceda, el menú muestra *Dar
  acceso de Accesibilidad…*.
- **Grabación de pantalla**: no hace falta.

## Uso

Haz clic en el icono de la barra de menús para abrir los ajustes. Activa o desactiva el efecto con el interruptor de
la parte superior del menú, con ⌃⌥⌘D o agitando el puntero rápido sin moverlo del sitio.

## Privacidad

Moody Dimmer no se conecta a la red por su cuenta: sin telemetría, sin analíticas y sin buscar actualizaciones en
segundo plano. La única consulta es cuando eliges *Buscar actualizaciones…*: la app pregunta a GitHub por el número de
la última versión y no descarga nada. El acceso de Accesibilidad solo sirve para encontrar la ventana activa y su
posición en la pantalla.

## Documentación

- [Ajustes](docs/settings.es.md): todos los ajustes y qué hace cada uno.
- [Compilación](docs/building.es.md): compilación, firma de código, el icono de la app.
- [Cómo funciona](docs/how-it-works.es.md): la superposición, el seguimiento del foco, solución de problemas,
  limitaciones.
- [Rendimiento y energía](docs/performance.es.md): cuánto cuesta y cómo se midió.

## Licencia

Copyright © 2026 roman1kuz. Moody Dimmer es software libre bajo la [GNU General Public License v3.0](LICENSE): puedes
usarlo, estudiarlo, modificarlo y compartirlo, y cualquier versión que distribuyas debe seguir abierta bajo la misma
licencia. El nombre «Moody Dimmer» y el icono de la app no están cubiertos por la licencia; consulta
[TRADEMARK.md](TRADEMARK.md).

Es un proyecto personal que se ofrece tal cual, sin garantía alguna. Depende de mecanismos internos no documentados de
macOS, así que una actualización del sistema podría romperlo (consulta las
[limitaciones](docs/how-it-works.es.md#limitaciones)).

---

Creado con la ayuda de [Claude](https://claude.ai), de Anthropic.
