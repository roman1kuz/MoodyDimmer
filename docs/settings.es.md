[English](settings.md) | [Русский](settings.ru.md) | [Español](settings.es.md)

# Ajustes

Todo está en el menú del icono de Moody Dimmer en la barra de menús. Los cambios se aplican al instante y se
recuerdan. El menú está en inglés, ruso y español. Las opciones con marca se activan y desactivan sin cerrar el menú,
así que puedes cambiar varias seguidas.

## Valores por defecto

| Ajuste | Por defecto |
|---|---|
| Efecto activado/desactivado | activado |
| Mantener iluminado | Todas las ventanas de la app |
| Quitar el efecto al arrastrar | activado |
| Oscurecer la barra de menús | activado |
| Oscurecer / Desenfoque / Grano | 50 % / no / no |
| Animación | 150 ms |
| Atajo de teclado | ⌃⌥⌘D |
| Agitar el puntero para alternar | activado |
| Icono de la barra de menús | Cascada, tema «Como el sistema» |
| Idioma | Como el sistema |
| Abrir al iniciar sesión | desactivado |

## Interruptor Moody Dimmer

El interruptor de la parte superior del menú activa o desactiva el efecto. Mientras está desactivado, el icono de la
barra de menús se ve atenuado y la app no hace nada: solo espera a que el efecto se vuelva a activar con el
interruptor, el atajo de teclado o agitando el puntero.

## Dar acceso de Accesibilidad…

Solo aparece mientras Moody Dimmer no tiene acceso de Accesibilidad. Abre *Ajustes del Sistema → Privacidad y
seguridad → Accesibilidad*. Sin acceso, el efecto sigue los cambios entre apps, pero no los cambios de ventana dentro
de una misma app (diálogos, una segunda ventana, ventanas que se mueven).

## Mantener iluminado

Qué sigue iluminado mientras todo lo demás se oscurece:

- **Solo la ventana activa**: solo la ventana delantera de la app activa. Foco estricto en una sola ventana.
- **Todas las ventanas de la app**: todas las ventanas visibles de la app activa, para que un diálogo o un panel no
  oscurezca la ventana principal de la app. Las ventanas de otras apps que queden encima siguen oscurecidas.

Cuando la app activa no tiene ventanas (cerraste la última, o una app se cerró y el foco no pasó a ninguna parte),
sigue iluminada con la misma regla la ventana superior que quede en pantalla, para que las ventanas restantes no se
pierdan en el fondo oscurecido. En el escritorio (Finder activo sin ventanas) y con la pantalla vacía no hay efecto.

## Comportamiento

- **Quitar el efecto al arrastrar**: cuando lo que arrastras (un archivo, un clip, un texto) sale de las ventanas de
  la app de origen, el efecto se desvanece para que veas dónde soltarlo. Vuelve al soltar el botón del ratón.
- **Oscurecer la barra de menús**: el efecto cubre también la barra de menús. En macOS 26 y posteriores la barra de
  menús es translúcida, así que con un oscurecimiento fuerte se vuelve oscura mientras sus iconos pueden seguir
  oscuros. Desactívalo para que el efecto termine en el borde inferior de la barra de menús. Con la barra de menús
  oculta automáticamente, el efecto siempre cubre toda la pantalla.

## Efecto

Tres controles definen los efectos y se pueden combinar: **Oscurecer** (una capa negra sobre el fondo), **Desenfoque**
(un desenfoque del fondo) y **Grano** (grano de película estático). Un control en 0 desactiva su efecto.

## Controles deslizantes

Arrastra un control, haz clic en cualquier punto o desplázate sobre él con el trackpad o la rueda del ratón. El valor
actual aparece a la derecha. El símbolo del control se mueve con el valor.

| Control | Rango | Cómo se traduce en el efecto |
|---|---|---|
| Oscurecer | no–100 % | opacidad de la capa negra = x (lineal; 100 % es negro total) |
| Desenfoque | no–100 % | radio = 50 × x^1,6 pt: 10 % ≈ 1, 30 % ≈ 7, 50 % ≈ 17, 80 % ≈ 35, 100 % = 50 |
| Grano | no–100 % | grano de película estático, opacidad = 0,5 × x^0,75 (los valores bajos siguen siendo visibles) |
| Animación | instantánea–400 ms | cuánto duran los cambios de foco y de efecto; *instantánea* cambia al momento |

## Activación rápida

Dos formas de activar o desactivar el efecto sin abrir el menú. Ambas funcionan en cualquier app y no necesitan
permisos adicionales.

- **Atajo de teclado**: ⌃⌥⌘D por defecto. Haz clic en el elemento y pulsa un atajo nuevo; debe incluir al menos una
  de las teclas ⌘, ⌥ o ⌃. Esc cancela, Suprimir quita el atajo. Las letras se muestran como en la distribución
  latina, sea cual sea la distribución activa.
- **Agitar el puntero para alternar**: agita el puntero sin moverlo del sitio, rápido y sin mucha amplitud: unos tres
  movimientos rápidos a izquierda y derecha en un segundo, de unos pocos centímetros como mucho. No lo activan los
  barridos amplios, los vaivenes lentos, los movimientos verticales o diagonales, un zigzag que cruza la pantalla, el
  apuntar pasándose del objetivo ni arrastrar. Si no lo usas, desactívalo: así la app deja de recibir los movimientos
  del puntero por completo.

## Icono de la barra de menús

- **Estilo**: *Cascada* (una ventana iluminada delante de otra oscurecida) o *Ventana* (una sola ventana).
- **Tema**:
  - *Como el sistema*: negro en modo claro, blanco en modo oscuro. Sigue el aspecto del sistema, incluido el modo
    automático según la hora del día.
  - *Claro*: siempre negro, para una barra de menús clara.
  - *Oscuro*: siempre blanco, para una barra de menús oscura.

## Idioma

*Como el sistema* elige el primero de inglés, ruso o español entre los idiomas preferidos del sistema; si no hay
ninguno, inglés. También puedes elegir *English*, *Русский* o *Español*. El menú cambia al instante, sin reabrir la app.

## Abrir al iniciar sesión

Abre Moody Dimmer al iniciar sesión.

## Buscar actualizaciones…

Pregunta a GitHub por la última versión, solo cuando eliges esta opción: la app nunca comprueba nada en segundo plano.
Mientras comprueba, la opción muestra un indicador de progreso y el menú sigue abierto. Si hay una versión nueva, el
aviso enlaza a su página de publicación. Si la app se instaló con Homebrew, el aviso también muestra el comando de
actualización (`brew update && brew upgrade moody-dimmer`) con un botón para copiarlo. La app no descarga ni instala
nada por sí misma.

## Salir

Cierra Moody Dimmer.

## Cuándo se aparta el efecto por sí solo

No hace falta ningún ajuste para esto:

- Spaces a pantalla completa (vídeo, reproductores, apps a pantalla completa) y ventanas sin bordes que cubren toda la
  pantalla (juegos);
- Mission Control, App Exposé y Mostrar escritorio;
- al arrastrar fuera de la app de origen (si *Quitar el efecto al arrastrar* está activado).
