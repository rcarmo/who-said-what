# Apple Speech versus Voz — workshop comparison

These are outputs from the same 120-second excerpt at recording time 00:10:00–00:12:00. The excerpt starts in Spanish, switches to English at about 00:11:06, and returns to Spanish at about 00:11:45. Apple used Spanish as the primary-language hint; both backends retain the app's normal language detection. This evaluates the current app configurations, including their routing behavior. No human reference transcript is available, so no WER ranking is claimed.

| Passage (excerpt time) | Voz | Apple Speech | Observation |
| --- | --- | --- | --- |
| Opening, 00:00 | “anuncios de BGP públicos” | “anuncios de BGP públicos” | Both preserve BGP. |
| Opening, 00:00 | “vienen de HL1” | “vienen de derecha uno” | Apple turns the apparent network-level identifier into ordinary words. |
| 00:32–00:36 | “Omistar Plus, el sincronismo” | “Movistar. Plus, el piconismo” | Apple gets Movistar; Voz produces the plausible technical term sincronismo. Both have errors. |
| English switch, 01:06 | “let me do this in English because it's easier” | “le me dohisglish because” | Voz handles the brief language change much better in this configuration. |
| 01:17–01:22 | “redundancy and failovers” | “redendancy and failloversising” | Apple's Spanish recognizer remains active through the short English section. |

The important difference is language routing. Voz is a multilingual decoder and can switch within a section. Apple SpeechTranscriber uses one locale per section. The app intentionally requires two agreeing 30-second detections before changing an established language, so this roughly 40-second English interruption does not trigger an Apple locale change. Its resulting English text is badly degraded. This does not establish that Apple's English model is intrinsically worse; a separate English smoke test transcribed correctly using its English locale.

The full Apple pass also contains repeated-word failures. Near 00:40:11, Voz produces “un nivel de tránsito y un nivel de acceso ... sus propios reflectores”; Apple repeats “de” across several cues. An isolated 45-second rerun starting at 00:39:55, using a Spanish primary hint, produces normal Spanish including the access/transit distinction and Juniper equipment. This points toward locale routing as a major contributor; the comparison does not isolate every model or long-context effect.

For this mixed-language workshop, **Voz is the safer default**. Apple's Spanish output is useful and sometimes improves proper names, but short switches remain a limitation of the current routing policy. Reducing visible language-label churn and recognizing short switches are separate concerns; an improvement would need a distinct routing policy and a new comparison, rather than assuming all Apple failures are recognition-model errors.

The full recording's readable audio is 02:57:26.656; the MP4 advertises four hours but is truncated or has an invalid sample index. Recognition-stage time was **81.37 seconds for Voz** and **122.33 seconds for Apple**. Overall wall times were 187.982 and 140.282 seconds respectively, but Who preparation/cache differences make those total times uneven comparisons of ASR speed. See [benchmark results](BENCHMARKS.md) for timings and caveats.

Local comparison files (generated files are ignored by Git):

- [Voz excerpt VTT](../benchmarks/excerpt/voz.vtt)
- [Apple excerpt VTT](../benchmarks/apple-ready/apple.vtt)
- [Voz full VTT](../benchmarks/full/voz.vtt)
- [Apple full VTT](../benchmarks/full-apple/apple.vtt)
