/*
 * Path data from Material Icons (androidx.compose.material:material-icons-extended 1.7.8),
 * Copyright The Android Open Source Project, Apache License 2.0.
 *
 * Only the icons the app uses, built with plain ImageVector builders, so the shared module needs
 * no icon library on any platform.
 */
package com.swiftshot.demo.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

private inline fun icon(name: String, autoMirror: Boolean, block: ImageVector.Builder.() -> ImageVector.Builder): ImageVector =
    ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f, autoMirror = autoMirror).block().build()

private inline fun ImageVector.Builder.materialPath(
    fillAlpha: Float = 1f,
    strokeAlpha: Float = 1f,
    pathFillType: PathFillType = PathFillType.NonZero,
    pathBuilder: PathBuilder.() -> Unit,
): ImageVector.Builder = path(
    fill = SolidColor(Color.Black),
    fillAlpha = fillAlpha,
    stroke = null,
    strokeAlpha = strokeAlpha,
    strokeLineWidth = 1f,
    strokeLineCap = StrokeCap.Butt,
    strokeLineJoin = StrokeJoin.Bevel,
    strokeLineMiter = 1f,
    pathFillType = pathFillType,
    pathBuilder = pathBuilder,
)

/** The app's Material icons: Rounded, Outlined and auto-mirrored Rounded. */
object AppIcons {
    object Rounded {
        val Add: ImageVector by lazy {
            icon("Rounded.Add", autoMirror = false) {
                materialPath {
                    moveTo(18.0f, 13.0f)
                    horizontalLineToRelative(-5.0f)
                    verticalLineToRelative(5.0f)
                    curveToRelative(0.0f, 0.55f, -0.45f, 1.0f, -1.0f, 1.0f)
                    reflectiveCurveToRelative(-1.0f, -0.45f, -1.0f, -1.0f)
                    verticalLineToRelative(-5.0f)
                    horizontalLineTo(6.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, -0.45f, -1.0f, -1.0f)
                    reflectiveCurveToRelative(0.45f, -1.0f, 1.0f, -1.0f)
                    horizontalLineToRelative(5.0f)
                    verticalLineTo(6.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(1.0f, 0.45f, 1.0f, 1.0f)
                    verticalLineToRelative(5.0f)
                    horizontalLineToRelative(5.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    close()
                }
            }
        }

        val CalendarMonth: ImageVector by lazy {
            icon("Rounded.CalendarMonth", autoMirror = false) {
                materialPath {
                    moveTo(17.0f, 2.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(1.0f)
                    horizontalLineTo(8.0f)
                    verticalLineTo(3.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    reflectiveCurveTo(6.0f, 2.45f, 6.0f, 3.0f)
                    verticalLineToRelative(1.0f)
                    horizontalLineTo(5.0f)
                    curveTo(3.89f, 4.0f, 3.01f, 4.9f, 3.01f, 6.0f)
                    lineTo(3.0f, 20.0f)
                    curveToRelative(0.0f, 1.1f, 0.89f, 2.0f, 2.0f, 2.0f)
                    horizontalLineToRelative(14.0f)
                    curveToRelative(1.1f, 0.0f, 2.0f, -0.9f, 2.0f, -2.0f)
                    verticalLineTo(6.0f)
                    curveToRelative(0.0f, -1.1f, -0.9f, -2.0f, -2.0f, -2.0f)
                    horizontalLineToRelative(-1.0f)
                    verticalLineTo(3.0f)
                    curveTo(18.0f, 2.45f, 17.55f, 2.0f, 17.0f, 2.0f)
                    close()
                    moveTo(19.0f, 20.0f)
                    horizontalLineTo(5.0f)
                    verticalLineTo(10.0f)
                    horizontalLineToRelative(14.0f)
                    verticalLineTo(20.0f)
                    close()
                    moveTo(11.0f, 13.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    reflectiveCurveTo(11.0f, 13.55f, 11.0f, 13.0f)
                    close()
                    moveTo(7.0f, 13.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    reflectiveCurveTo(7.0f, 13.55f, 7.0f, 13.0f)
                    close()
                    moveTo(15.0f, 13.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    reflectiveCurveTo(15.0f, 13.55f, 15.0f, 13.0f)
                    close()
                    moveTo(11.0f, 17.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    reflectiveCurveTo(11.0f, 17.55f, 11.0f, 17.0f)
                    close()
                    moveTo(7.0f, 17.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    reflectiveCurveTo(7.0f, 17.55f, 7.0f, 17.0f)
                    close()
                    moveTo(15.0f, 17.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    reflectiveCurveTo(15.0f, 17.55f, 15.0f, 17.0f)
                    close()
                }
            }
        }

        val CheckCircle: ImageVector by lazy {
            icon("Rounded.CheckCircle", autoMirror = false) {
                materialPath {
                    moveTo(12.0f, 2.0f)
                    curveTo(6.48f, 2.0f, 2.0f, 6.48f, 2.0f, 12.0f)
                    reflectiveCurveToRelative(4.48f, 10.0f, 10.0f, 10.0f)
                    reflectiveCurveToRelative(10.0f, -4.48f, 10.0f, -10.0f)
                    reflectiveCurveTo(17.52f, 2.0f, 12.0f, 2.0f)
                    close()
                    moveTo(9.29f, 16.29f)
                    lineTo(5.7f, 12.7f)
                    curveToRelative(-0.39f, -0.39f, -0.39f, -1.02f, 0.0f, -1.41f)
                    curveToRelative(0.39f, -0.39f, 1.02f, -0.39f, 1.41f, 0.0f)
                    lineTo(10.0f, 14.17f)
                    lineToRelative(6.88f, -6.88f)
                    curveToRelative(0.39f, -0.39f, 1.02f, -0.39f, 1.41f, 0.0f)
                    curveToRelative(0.39f, 0.39f, 0.39f, 1.02f, 0.0f, 1.41f)
                    lineToRelative(-7.59f, 7.59f)
                    curveToRelative(-0.38f, 0.39f, -1.02f, 0.39f, -1.41f, 0.0f)
                    close()
                }
            }
        }

        val Insights: ImageVector by lazy {
            icon("Rounded.Insights", autoMirror = false) {
                materialPath {
                    moveTo(21.0f, 8.0f)
                    curveToRelative(-1.45f, 0.0f, -2.26f, 1.44f, -1.93f, 2.51f)
                    lineToRelative(-3.55f, 3.56f)
                    curveToRelative(-0.3f, -0.09f, -0.74f, -0.09f, -1.04f, 0.0f)
                    lineToRelative(-2.55f, -2.55f)
                    curveTo(12.27f, 10.45f, 11.46f, 9.0f, 10.0f, 9.0f)
                    curveToRelative(-1.45f, 0.0f, -2.27f, 1.44f, -1.93f, 2.52f)
                    lineToRelative(-4.56f, 4.55f)
                    curveTo(2.44f, 15.74f, 1.0f, 16.55f, 1.0f, 18.0f)
                    curveToRelative(0.0f, 1.1f, 0.9f, 2.0f, 2.0f, 2.0f)
                    curveToRelative(1.45f, 0.0f, 2.26f, -1.44f, 1.93f, -2.51f)
                    lineToRelative(4.55f, -4.56f)
                    curveToRelative(0.3f, 0.09f, 0.74f, 0.09f, 1.04f, 0.0f)
                    lineToRelative(2.55f, 2.55f)
                    curveTo(12.73f, 16.55f, 13.54f, 18.0f, 15.0f, 18.0f)
                    curveToRelative(1.45f, 0.0f, 2.27f, -1.44f, 1.93f, -2.52f)
                    lineToRelative(3.56f, -3.55f)
                    curveTo(21.56f, 12.26f, 23.0f, 11.45f, 23.0f, 10.0f)
                    curveTo(23.0f, 8.9f, 22.1f, 8.0f, 21.0f, 8.0f)
                    close()
                }
                materialPath {
                    moveTo(15.0f, 9.0f)
                    lineToRelative(0.94f, -2.07f)
                    lineToRelative(2.06f, -0.93f)
                    lineToRelative(-2.06f, -0.93f)
                    lineToRelative(-0.94f, -2.07f)
                    lineToRelative(-0.92f, 2.07f)
                    lineToRelative(-2.08f, 0.93f)
                    lineToRelative(2.08f, 0.93f)
                    close()
                }
                materialPath {
                    moveTo(3.5f, 11.0f)
                    lineToRelative(0.5f, -2.0f)
                    lineToRelative(2.0f, -0.5f)
                    lineToRelative(-2.0f, -0.5f)
                    lineToRelative(-0.5f, -2.0f)
                    lineToRelative(-0.5f, 2.0f)
                    lineToRelative(-2.0f, 0.5f)
                    lineToRelative(2.0f, 0.5f)
                    close()
                }
            }
        }

        val Settings: ImageVector by lazy {
            icon("Rounded.Settings", autoMirror = false) {
                materialPath {
                    moveTo(19.5f, 12.0f)
                    curveToRelative(0.0f, -0.23f, -0.01f, -0.45f, -0.03f, -0.68f)
                    lineToRelative(1.86f, -1.41f)
                    curveToRelative(0.4f, -0.3f, 0.51f, -0.86f, 0.26f, -1.3f)
                    lineToRelative(-1.87f, -3.23f)
                    curveToRelative(-0.25f, -0.44f, -0.79f, -0.62f, -1.25f, -0.42f)
                    lineToRelative(-2.15f, 0.91f)
                    curveToRelative(-0.37f, -0.26f, -0.76f, -0.49f, -1.17f, -0.68f)
                    lineToRelative(-0.29f, -2.31f)
                    curveTo(14.8f, 2.38f, 14.37f, 2.0f, 13.87f, 2.0f)
                    horizontalLineToRelative(-3.73f)
                    curveTo(9.63f, 2.0f, 9.2f, 2.38f, 9.14f, 2.88f)
                    lineTo(8.85f, 5.19f)
                    curveToRelative(-0.41f, 0.19f, -0.8f, 0.42f, -1.17f, 0.68f)
                    lineTo(5.53f, 4.96f)
                    curveToRelative(-0.46f, -0.2f, -1.0f, -0.02f, -1.25f, 0.42f)
                    lineTo(2.41f, 8.62f)
                    curveToRelative(-0.25f, 0.44f, -0.14f, 0.99f, 0.26f, 1.3f)
                    lineToRelative(1.86f, 1.41f)
                    curveTo(4.51f, 11.55f, 4.5f, 11.77f, 4.5f, 12.0f)
                    reflectiveCurveToRelative(0.01f, 0.45f, 0.03f, 0.68f)
                    lineToRelative(-1.86f, 1.41f)
                    curveToRelative(-0.4f, 0.3f, -0.51f, 0.86f, -0.26f, 1.3f)
                    lineToRelative(1.87f, 3.23f)
                    curveToRelative(0.25f, 0.44f, 0.79f, 0.62f, 1.25f, 0.42f)
                    lineToRelative(2.15f, -0.91f)
                    curveToRelative(0.37f, 0.26f, 0.76f, 0.49f, 1.17f, 0.68f)
                    lineToRelative(0.29f, 2.31f)
                    curveTo(9.2f, 21.62f, 9.63f, 22.0f, 10.13f, 22.0f)
                    horizontalLineToRelative(3.73f)
                    curveToRelative(0.5f, 0.0f, 0.93f, -0.38f, 0.99f, -0.88f)
                    lineToRelative(0.29f, -2.31f)
                    curveToRelative(0.41f, -0.19f, 0.8f, -0.42f, 1.17f, -0.68f)
                    lineToRelative(2.15f, 0.91f)
                    curveToRelative(0.46f, 0.2f, 1.0f, 0.02f, 1.25f, -0.42f)
                    lineToRelative(1.87f, -3.23f)
                    curveToRelative(0.25f, -0.44f, 0.14f, -0.99f, -0.26f, -1.3f)
                    lineToRelative(-1.86f, -1.41f)
                    curveTo(19.49f, 12.45f, 19.5f, 12.23f, 19.5f, 12.0f)
                    close()
                    moveTo(12.04f, 15.5f)
                    curveToRelative(-1.93f, 0.0f, -3.5f, -1.57f, -3.5f, -3.5f)
                    reflectiveCurveToRelative(1.57f, -3.5f, 3.5f, -3.5f)
                    reflectiveCurveToRelative(3.5f, 1.57f, 3.5f, 3.5f)
                    reflectiveCurveTo(13.97f, 15.5f, 12.04f, 15.5f)
                    close()
                }
            }
        }

        val WaterDrop: ImageVector by lazy {
            icon("Rounded.WaterDrop", autoMirror = false) {
                materialPath {
                    moveTo(12.66f, 2.58f)
                    curveToRelative(-0.38f, -0.33f, -0.95f, -0.33f, -1.33f, 0.0f)
                    curveTo(6.45f, 6.88f, 4.0f, 10.62f, 4.0f, 13.8f)
                    curveToRelative(0.0f, 4.98f, 3.8f, 8.2f, 8.0f, 8.2f)
                    reflectiveCurveToRelative(8.0f, -3.22f, 8.0f, -8.2f)
                    curveTo(20.0f, 10.62f, 17.55f, 6.88f, 12.66f, 2.58f)
                    close()
                    moveTo(7.83f, 14.0f)
                    curveToRelative(0.37f, 0.0f, 0.67f, 0.26f, 0.74f, 0.62f)
                    curveToRelative(0.41f, 2.22f, 2.28f, 2.98f, 3.64f, 2.87f)
                    curveToRelative(0.43f, -0.02f, 0.79f, 0.32f, 0.79f, 0.75f)
                    curveToRelative(0.0f, 0.4f, -0.32f, 0.73f, -0.72f, 0.75f)
                    curveToRelative(-2.13f, 0.13f, -4.62f, -1.09f, -5.19f, -4.12f)
                    curveTo(7.01f, 14.42f, 7.37f, 14.0f, 7.83f, 14.0f)
                    close()
                }
            }
        }

        val EditNote: ImageVector by lazy {
            icon("Rounded.EditNote", autoMirror = false) {
                materialPath {
                    moveTo(14.0f, 11.0f)
                    curveToRelative(0.0f, 0.55f, -0.45f, 1.0f, -1.0f, 1.0f)
                    horizontalLineTo(4.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, -0.45f, -1.0f, -1.0f)
                    reflectiveCurveToRelative(0.45f, -1.0f, 1.0f, -1.0f)
                    horizontalLineToRelative(9.0f)
                    curveTo(13.55f, 10.0f, 14.0f, 10.45f, 14.0f, 11.0f)
                    close()
                    moveTo(3.0f, 7.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    horizontalLineToRelative(9.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(-0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineTo(4.0f)
                    curveTo(3.45f, 6.0f, 3.0f, 6.45f, 3.0f, 7.0f)
                    close()
                    moveTo(10.0f, 15.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineTo(4.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    reflectiveCurveToRelative(0.45f, 1.0f, 1.0f, 1.0f)
                    horizontalLineToRelative(5.0f)
                    curveTo(9.55f, 16.0f, 10.0f, 15.55f, 10.0f, 15.0f)
                    close()
                    moveTo(18.01f, 12.87f)
                    lineToRelative(0.71f, -0.71f)
                    curveToRelative(0.39f, -0.39f, 1.02f, -0.39f, 1.41f, 0.0f)
                    lineToRelative(0.71f, 0.71f)
                    curveToRelative(0.39f, 0.39f, 0.39f, 1.02f, 0.0f, 1.41f)
                    lineToRelative(-0.71f, 0.71f)
                    lineTo(18.01f, 12.87f)
                    close()
                    moveTo(17.3f, 13.58f)
                    lineToRelative(-5.16f, 5.16f)
                    curveTo(12.05f, 18.83f, 12.0f, 18.95f, 12.0f, 19.09f)
                    verticalLineToRelative(1.41f)
                    curveToRelative(0.0f, 0.28f, 0.22f, 0.5f, 0.5f, 0.5f)
                    horizontalLineToRelative(1.41f)
                    curveToRelative(0.13f, 0.0f, 0.26f, -0.05f, 0.35f, -0.15f)
                    lineToRelative(5.16f, -5.16f)
                    lineTo(17.3f, 13.58f)
                    close()
                }
            }
        }

        val SelfImprovement: ImageVector by lazy {
            icon("Rounded.SelfImprovement", autoMirror = false) {
                materialPath {
                    moveTo(12.0f, 6.0f)
                    moveToRelative(-2.0f, 0.0f)
                    arcToRelative(2.0f, 2.0f, 0.0f, true, true, 4.0f, 0.0f)
                    arcToRelative(2.0f, 2.0f, 0.0f, true, true, -4.0f, 0.0f)
                }
                materialPath {
                    moveTo(21.0f, 14.94f)
                    lineTo(21.0f, 14.94f)
                    curveToRelative(0.0f, -0.5f, -0.36f, -0.93f, -0.85f, -0.98f)
                    curveToRelative(-1.88f, -0.21f, -3.49f, -1.13f, -4.75f, -2.63f)
                    lineToRelative(-1.34f, -1.6f)
                    curveTo(13.68f, 9.26f, 13.12f, 9.0f, 12.53f, 9.0f)
                    horizontalLineToRelative(-1.05f)
                    curveToRelative(-0.59f, 0.0f, -1.15f, 0.26f, -1.53f, 0.72f)
                    lineToRelative(-1.34f, 1.6f)
                    curveToRelative(-1.25f, 1.5f, -2.87f, 2.42f, -4.75f, 2.63f)
                    curveTo(3.36f, 14.01f, 3.0f, 14.44f, 3.0f, 14.94f)
                    verticalLineToRelative(0.0f)
                    curveToRelative(0.0f, 0.6f, 0.53f, 1.07f, 1.13f, 1.0f)
                    curveToRelative(2.3f, -0.27f, 4.32f, -1.39f, 5.87f, -3.19f)
                    verticalLineTo(15.0f)
                    lineToRelative(-3.76f, 1.5f)
                    curveToRelative(-0.65f, 0.26f, -1.16f, 0.83f, -1.23f, 1.53f)
                    curveTo(4.91f, 19.1f, 5.74f, 20.0f, 6.79f, 20.0f)
                    horizontalLineTo(9.0f)
                    verticalLineToRelative(-0.5f)
                    curveToRelative(0.0f, -1.38f, 1.12f, -2.5f, 2.5f, -2.5f)
                    horizontalLineToRelative(3.0f)
                    curveToRelative(0.28f, 0.0f, 0.5f, 0.22f, 0.5f, 0.5f)
                    reflectiveCurveTo(14.78f, 18.0f, 14.5f, 18.0f)
                    horizontalLineToRelative(-3.0f)
                    curveToRelative(-0.83f, 0.0f, -1.5f, 0.67f, -1.5f, 1.5f)
                    verticalLineTo(20.0f)
                    lineToRelative(7.1f, 0.0f)
                    curveToRelative(0.85f, 0.0f, 1.65f, -0.54f, 1.85f, -1.37f)
                    curveToRelative(0.21f, -0.89f, -0.27f, -1.76f, -1.08f, -2.08f)
                    lineTo(14.0f, 15.0f)
                    verticalLineToRelative(-2.25f)
                    curveToRelative(1.56f, 1.8f, 3.57f, 2.91f, 5.87f, 3.19f)
                    curveTo(20.47f, 16.0f, 21.0f, 15.54f, 21.0f, 14.94f)
                    close()
                }
            }
        }

        val CloudSync: ImageVector by lazy {
            icon("Rounded.CloudSync", autoMirror = false) {
                materialPath {
                    moveTo(24.0f, 17.48f)
                    curveToRelative(0.0f, 1.38f, -1.12f, 2.5f, -2.5f, 2.5f)
                    lineTo(15.0f, 20.0f)
                    curveToRelative(-1.66f, 0.0f, -3.0f, -1.34f, -3.0f, -3.0f)
                    curveToRelative(0.0f, -1.6f, 1.26f, -2.9f, 2.84f, -2.98f)
                    curveTo(15.4f, 12.83f, 16.6f, 12.0f, 18.0f, 12.0f)
                    curveToRelative(1.76f, 0.0f, 3.2f, 1.3f, 3.45f, 2.99f)
                    curveToRelative(0.02f, 0.0f, 0.03f, -0.01f, 0.05f, -0.01f)
                    curveTo(22.88f, 14.98f, 24.0f, 16.1f, 24.0f, 17.48f)
                    close()
                    moveTo(10.0f, 15.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    reflectiveCurveToRelative(-1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(1.44f)
                    curveToRelative(-1.22f, -1.1f, -2.0f, -2.67f, -2.0f, -4.44f)
                    curveToRelative(0.0f, -2.38f, 1.39f, -4.43f, 3.4f, -5.4f)
                    curveTo(9.77f, 6.42f, 10.0f, 6.04f, 10.0f, 5.63f)
                    curveToRelative(0.0f, -0.71f, -0.73f, -1.18f, -1.37f, -0.88f)
                    curveTo(5.89f, 6.03f, 4.0f, 8.79f, 4.0f, 12.0f)
                    curveToRelative(0.0f, 2.4f, 1.06f, 4.54f, 2.73f, 6.0f)
                    horizontalLineTo(5.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    reflectiveCurveToRelative(0.45f, 1.0f, 1.0f, 1.0f)
                    horizontalLineToRelative(4.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineTo(15.0f)
                    close()
                    moveTo(19.0f, 6.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(-0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineToRelative(-4.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(4.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineTo(7.56f)
                    curveToRelative(0.98f, 0.89f, 1.68f, 2.08f, 1.92f, 3.44f)
                    lineToRelative(2.02f, 0.0f)
                    curveToRelative(-0.25f, -1.99f, -1.23f, -3.74f, -2.66f, -5.0f)
                    horizontalLineTo(19.0f)
                    close()
                }
            }
        }

        val Contrast: ImageVector by lazy {
            icon("Rounded.Contrast", autoMirror = false) {
                materialPath {
                    moveTo(12.0f, 22.0f)
                    curveToRelative(5.52f, 0.0f, 10.0f, -4.48f, 10.0f, -10.0f)
                    reflectiveCurveTo(17.52f, 2.0f, 12.0f, 2.0f)
                    reflectiveCurveTo(2.0f, 6.48f, 2.0f, 12.0f)
                    reflectiveCurveTo(6.48f, 22.0f, 12.0f, 22.0f)
                    close()
                    moveTo(13.0f, 4.07f)
                    curveToRelative(3.94f, 0.49f, 7.0f, 3.85f, 7.0f, 7.93f)
                    reflectiveCurveToRelative(-3.05f, 7.44f, -7.0f, 7.93f)
                    verticalLineTo(4.07f)
                    close()
                }
            }
        }

        val MonitorHeart: ImageVector by lazy {
            icon("Rounded.MonitorHeart", autoMirror = false) {
                materialPath {
                    moveTo(15.11f, 12.45f)
                    lineTo(14.0f, 10.24f)
                    lineToRelative(-3.11f, 6.21f)
                    curveTo(10.73f, 16.79f, 10.38f, 17.0f, 10.0f, 17.0f)
                    reflectiveCurveToRelative(-0.73f, -0.21f, -0.89f, -0.55f)
                    lineTo(7.38f, 13.0f)
                    horizontalLineTo(2.0f)
                    verticalLineToRelative(5.0f)
                    curveToRelative(0.0f, 1.1f, 0.9f, 2.0f, 2.0f, 2.0f)
                    horizontalLineToRelative(16.0f)
                    curveToRelative(1.1f, 0.0f, 2.0f, -0.9f, 2.0f, -2.0f)
                    verticalLineToRelative(-5.0f)
                    horizontalLineToRelative(-6.0f)
                    curveTo(15.62f, 13.0f, 15.27f, 12.79f, 15.11f, 12.45f)
                    close()
                }
                materialPath {
                    moveTo(20.0f, 4.0f)
                    horizontalLineTo(4.0f)
                    curveTo(2.9f, 4.0f, 2.0f, 4.9f, 2.0f, 6.0f)
                    verticalLineToRelative(5.0f)
                    horizontalLineToRelative(6.0f)
                    curveToRelative(0.38f, 0.0f, 0.73f, 0.21f, 0.89f, 0.55f)
                    lineTo(10.0f, 13.76f)
                    lineToRelative(3.11f, -6.21f)
                    curveToRelative(0.34f, -0.68f, 1.45f, -0.68f, 1.79f, 0.0f)
                    lineTo(16.62f, 11.0f)
                    horizontalLineTo(22.0f)
                    verticalLineTo(6.0f)
                    curveTo(22.0f, 4.9f, 21.1f, 4.0f, 20.0f, 4.0f)
                    close()
                }
            }
        }

        val NotificationsActive: ImageVector by lazy {
            icon("Rounded.NotificationsActive", autoMirror = false) {
                materialPath {
                    moveTo(18.0f, 16.0f)
                    verticalLineToRelative(-5.0f)
                    curveToRelative(0.0f, -3.07f, -1.64f, -5.64f, -4.5f, -6.32f)
                    lineTo(13.5f, 4.0f)
                    curveToRelative(0.0f, -0.83f, -0.68f, -1.5f, -1.51f, -1.5f)
                    reflectiveCurveTo(10.5f, 3.17f, 10.5f, 4.0f)
                    verticalLineToRelative(0.68f)
                    curveTo(7.63f, 5.36f, 6.0f, 7.92f, 6.0f, 11.0f)
                    verticalLineToRelative(5.0f)
                    lineToRelative(-1.3f, 1.29f)
                    curveToRelative(-0.63f, 0.63f, -0.19f, 1.71f, 0.7f, 1.71f)
                    horizontalLineToRelative(13.17f)
                    curveToRelative(0.89f, 0.0f, 1.34f, -1.08f, 0.71f, -1.71f)
                    lineTo(18.0f, 16.0f)
                    close()
                    moveTo(11.99f, 22.0f)
                    curveToRelative(1.1f, 0.0f, 2.0f, -0.9f, 2.0f, -2.0f)
                    horizontalLineToRelative(-4.0f)
                    curveToRelative(0.0f, 1.1f, 0.89f, 2.0f, 2.0f, 2.0f)
                    close()
                    moveTo(6.77f, 4.73f)
                    curveToRelative(0.42f, -0.38f, 0.43f, -1.03f, 0.03f, -1.43f)
                    curveToRelative(-0.38f, -0.38f, -1.0f, -0.39f, -1.39f, -0.02f)
                    curveTo(3.7f, 4.84f, 2.52f, 6.96f, 2.14f, 9.34f)
                    curveToRelative(-0.09f, 0.61f, 0.38f, 1.16f, 1.0f, 1.16f)
                    curveToRelative(0.48f, 0.0f, 0.9f, -0.35f, 0.98f, -0.83f)
                    curveToRelative(0.3f, -1.94f, 1.26f, -3.67f, 2.65f, -4.94f)
                    close()
                    moveTo(18.6f, 3.28f)
                    curveToRelative(-0.4f, -0.37f, -1.02f, -0.36f, -1.4f, 0.02f)
                    curveToRelative(-0.4f, 0.4f, -0.38f, 1.04f, 0.03f, 1.42f)
                    curveToRelative(1.38f, 1.27f, 2.35f, 3.0f, 2.65f, 4.94f)
                    curveToRelative(0.07f, 0.48f, 0.49f, 0.83f, 0.98f, 0.83f)
                    curveToRelative(0.61f, 0.0f, 1.09f, -0.55f, 0.99f, -1.16f)
                    curveToRelative(-0.38f, -2.37f, -1.55f, -4.48f, -3.25f, -6.05f)
                    close()
                }
            }
        }

        val Schedule: ImageVector by lazy {
            icon("Rounded.Schedule", autoMirror = false) {
                materialPath {
                    moveTo(11.99f, 2.0f)
                    curveTo(6.47f, 2.0f, 2.0f, 6.48f, 2.0f, 12.0f)
                    reflectiveCurveToRelative(4.47f, 10.0f, 9.99f, 10.0f)
                    curveTo(17.52f, 22.0f, 22.0f, 17.52f, 22.0f, 12.0f)
                    reflectiveCurveTo(17.52f, 2.0f, 11.99f, 2.0f)
                    close()
                    moveTo(12.0f, 20.0f)
                    curveToRelative(-4.42f, 0.0f, -8.0f, -3.58f, -8.0f, -8.0f)
                    reflectiveCurveToRelative(3.58f, -8.0f, 8.0f, -8.0f)
                    reflectiveCurveToRelative(8.0f, 3.58f, 8.0f, 8.0f)
                    reflectiveCurveToRelative(-3.58f, 8.0f, -8.0f, 8.0f)
                    close()
                    moveTo(11.78f, 7.0f)
                    horizontalLineToRelative(-0.06f)
                    curveToRelative(-0.4f, 0.0f, -0.72f, 0.32f, -0.72f, 0.72f)
                    verticalLineToRelative(4.72f)
                    curveToRelative(0.0f, 0.35f, 0.18f, 0.68f, 0.49f, 0.86f)
                    lineToRelative(4.15f, 2.49f)
                    curveToRelative(0.34f, 0.2f, 0.78f, 0.1f, 0.98f, -0.24f)
                    curveToRelative(0.21f, -0.34f, 0.1f, -0.79f, -0.25f, -0.99f)
                    lineToRelative(-3.87f, -2.3f)
                    lineTo(12.5f, 7.72f)
                    curveToRelative(0.0f, -0.4f, -0.32f, -0.72f, -0.72f, -0.72f)
                    close()
                }
            }
        }

        val Shield: ImageVector by lazy {
            icon("Rounded.Shield", autoMirror = false) {
                materialPath {
                    moveTo(11.3f, 2.26f)
                    lineToRelative(-6.0f, 2.25f)
                    curveTo(4.52f, 4.81f, 4.0f, 5.55f, 4.0f, 6.39f)
                    verticalLineToRelative(4.7f)
                    curveToRelative(0.0f, 4.83f, 3.13f, 9.37f, 7.43f, 10.75f)
                    curveToRelative(0.37f, 0.12f, 0.77f, 0.12f, 1.14f, 0.0f)
                    curveToRelative(4.3f, -1.38f, 7.43f, -5.91f, 7.43f, -10.75f)
                    verticalLineToRelative(-4.7f)
                    curveToRelative(0.0f, -0.83f, -0.52f, -1.58f, -1.3f, -1.87f)
                    lineToRelative(-6.0f, -2.25f)
                    curveTo(12.25f, 2.09f, 11.75f, 2.09f, 11.3f, 2.26f)
                    close()
                }
            }
        }

        val StarOutline: ImageVector by lazy {
            icon("Rounded.StarOutline", autoMirror = false) {
                materialPath {
                    moveTo(19.65f, 9.04f)
                    lineToRelative(-4.84f, -0.42f)
                    lineToRelative(-1.89f, -4.45f)
                    curveToRelative(-0.34f, -0.81f, -1.5f, -0.81f, -1.84f, 0.0f)
                    lineTo(9.19f, 8.63f)
                    lineToRelative(-4.83f, 0.41f)
                    curveToRelative(-0.88f, 0.07f, -1.24f, 1.17f, -0.57f, 1.75f)
                    lineToRelative(3.67f, 3.18f)
                    lineToRelative(-1.1f, 4.72f)
                    curveToRelative(-0.2f, 0.86f, 0.73f, 1.54f, 1.49f, 1.08f)
                    lineToRelative(4.15f, -2.5f)
                    lineToRelative(4.15f, 2.51f)
                    curveToRelative(0.76f, 0.46f, 1.69f, -0.22f, 1.49f, -1.08f)
                    lineToRelative(-1.1f, -4.73f)
                    lineToRelative(3.67f, -3.18f)
                    curveToRelative(0.67f, -0.58f, 0.32f, -1.68f, -0.56f, -1.75f)
                    close()
                    moveTo(12.0f, 15.4f)
                    lineToRelative(-3.76f, 2.27f)
                    lineToRelative(1.0f, -4.28f)
                    lineToRelative(-3.32f, -2.88f)
                    lineToRelative(4.38f, -0.38f)
                    lineTo(12.0f, 6.1f)
                    lineToRelative(1.71f, 4.04f)
                    lineToRelative(4.38f, 0.38f)
                    lineToRelative(-3.32f, 2.88f)
                    lineToRelative(1.0f, 4.28f)
                    lineTo(12.0f, 15.4f)
                    close()
                }
            }
        }

        val Upload: ImageVector by lazy {
            icon("Rounded.Upload", autoMirror = false) {
                materialPath {
                    moveTo(10.0f, 16.0f)
                    horizontalLineToRelative(4.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineToRelative(-5.0f)
                    horizontalLineToRelative(1.59f)
                    curveToRelative(0.89f, 0.0f, 1.34f, -1.08f, 0.71f, -1.71f)
                    lineTo(12.71f, 3.7f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    lineTo(6.71f, 8.29f)
                    curveToRelative(-0.63f, 0.63f, -0.19f, 1.71f, 0.7f, 1.71f)
                    lineTo(9.0f, 10.0f)
                    verticalLineToRelative(5.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    close()
                    moveTo(6.0f, 18.0f)
                    horizontalLineToRelative(12.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, 0.45f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(-0.45f, 1.0f, -1.0f, 1.0f)
                    lineTo(6.0f, 20.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, -0.45f, -1.0f, -1.0f)
                    reflectiveCurveToRelative(0.45f, -1.0f, 1.0f, -1.0f)
                    close()
                }
            }
        }

        val Bedtime: ImageVector by lazy {
            icon("Rounded.Bedtime", autoMirror = false) {
                materialPath {
                    moveTo(11.65f, 3.46f)
                    curveToRelative(0.27f, -0.71f, -0.36f, -1.45f, -1.12f, -1.34f)
                    curveToRelative(-5.52f, 0.8f, -9.47f, 6.07f, -8.34f, 11.88f)
                    curveToRelative(0.78f, 4.02f, 4.09f, 7.21f, 8.14f, 7.87f)
                    curveToRelative(3.74f, 0.61f, 7.16f, -0.87f, 9.32f, -3.44f)
                    curveToRelative(0.48f, -0.57f, 0.19f, -1.48f, -0.55f, -1.62f)
                    curveTo(13.08f, 15.66f, 9.42f, 9.27f, 11.65f, 3.46f)
                    close()
                }
            }
        }

        val Close: ImageVector by lazy {
            icon("Rounded.Close", autoMirror = false) {
                materialPath {
                    moveTo(18.3f, 5.71f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    lineTo(12.0f, 10.59f)
                    lineTo(7.11f, 5.7f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    curveToRelative(-0.39f, 0.39f, -0.39f, 1.02f, 0.0f, 1.41f)
                    lineTo(10.59f, 12.0f)
                    lineTo(5.7f, 16.89f)
                    curveToRelative(-0.39f, 0.39f, -0.39f, 1.02f, 0.0f, 1.41f)
                    curveToRelative(0.39f, 0.39f, 1.02f, 0.39f, 1.41f, 0.0f)
                    lineTo(12.0f, 13.41f)
                    lineToRelative(4.89f, 4.89f)
                    curveToRelative(0.39f, 0.39f, 1.02f, 0.39f, 1.41f, 0.0f)
                    curveToRelative(0.39f, -0.39f, 0.39f, -1.02f, 0.0f, -1.41f)
                    lineTo(13.41f, 12.0f)
                    lineToRelative(4.89f, -4.89f)
                    curveToRelative(0.38f, -0.38f, 0.38f, -1.02f, 0.0f, -1.4f)
                    close()
                }
            }
        }

        val DeleteOutline: ImageVector by lazy {
            icon("Rounded.DeleteOutline", autoMirror = false) {
                materialPath {
                    moveTo(6.0f, 19.0f)
                    curveToRelative(0.0f, 1.1f, 0.9f, 2.0f, 2.0f, 2.0f)
                    horizontalLineToRelative(8.0f)
                    curveToRelative(1.1f, 0.0f, 2.0f, -0.9f, 2.0f, -2.0f)
                    lineTo(18.0f, 9.0f)
                    curveToRelative(0.0f, -1.1f, -0.9f, -2.0f, -2.0f, -2.0f)
                    lineTo(8.0f, 7.0f)
                    curveToRelative(-1.1f, 0.0f, -2.0f, 0.9f, -2.0f, 2.0f)
                    verticalLineToRelative(10.0f)
                    close()
                    moveTo(9.0f, 9.0f)
                    horizontalLineToRelative(6.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, 0.45f, 1.0f, 1.0f)
                    verticalLineToRelative(8.0f)
                    curveToRelative(0.0f, 0.55f, -0.45f, 1.0f, -1.0f, 1.0f)
                    lineTo(9.0f, 19.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, -0.45f, -1.0f, -1.0f)
                    verticalLineToRelative(-8.0f)
                    curveToRelative(0.0f, -0.55f, 0.45f, -1.0f, 1.0f, -1.0f)
                    close()
                    moveTo(15.5f, 4.0f)
                    lineToRelative(-0.71f, -0.71f)
                    curveToRelative(-0.18f, -0.18f, -0.44f, -0.29f, -0.7f, -0.29f)
                    lineTo(9.91f, 3.0f)
                    curveToRelative(-0.26f, 0.0f, -0.52f, 0.11f, -0.7f, 0.29f)
                    lineTo(8.5f, 4.0f)
                    lineTo(6.0f, 4.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    reflectiveCurveToRelative(0.45f, 1.0f, 1.0f, 1.0f)
                    horizontalLineToRelative(12.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    reflectiveCurveToRelative(-0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineToRelative(-2.5f)
                    close()
                }
            }
        }

        val Repeat: ImageVector by lazy {
            icon("Rounded.Repeat", autoMirror = false) {
                materialPath {
                    moveTo(7.0f, 7.0f)
                    horizontalLineToRelative(10.0f)
                    verticalLineToRelative(1.79f)
                    curveToRelative(0.0f, 0.45f, 0.54f, 0.67f, 0.85f, 0.35f)
                    lineToRelative(2.79f, -2.79f)
                    curveToRelative(0.2f, -0.2f, 0.2f, -0.51f, 0.0f, -0.71f)
                    lineToRelative(-2.79f, -2.79f)
                    curveToRelative(-0.31f, -0.31f, -0.85f, -0.09f, -0.85f, 0.36f)
                    lineTo(17.0f, 5.0f)
                    lineTo(6.0f, 5.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(4.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(1.0f, -0.45f, 1.0f, -1.0f)
                    lineTo(7.0f, 7.0f)
                    close()
                    moveTo(17.0f, 17.0f)
                    lineTo(7.0f, 17.0f)
                    verticalLineToRelative(-1.79f)
                    curveToRelative(0.0f, -0.45f, -0.54f, -0.67f, -0.85f, -0.35f)
                    lineToRelative(-2.79f, 2.79f)
                    curveToRelative(-0.2f, 0.2f, -0.2f, 0.51f, 0.0f, 0.71f)
                    lineToRelative(2.79f, 2.79f)
                    curveToRelative(0.31f, 0.31f, 0.85f, 0.09f, 0.85f, -0.36f)
                    lineTo(7.0f, 19.0f)
                    horizontalLineToRelative(11.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineToRelative(-4.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    reflectiveCurveToRelative(-1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(3.0f)
                    close()
                }
            }
        }

        val LocalFireDepartment: ImageVector by lazy {
            icon("Rounded.LocalFireDepartment", autoMirror = false) {
                materialPath {
                    moveTo(12.0f, 12.9f)
                    lineToRelative(-2.03f, 2.0f)
                    curveToRelative(-0.46f, 0.46f, -0.82f, 1.03f, -0.93f, 1.67f)
                    curveTo(8.74f, 18.41f, 10.18f, 20.0f, 12.0f, 20.0f)
                    reflectiveCurveToRelative(3.26f, -1.59f, 2.96f, -3.42f)
                    curveToRelative(-0.11f, -0.64f, -0.46f, -1.22f, -0.93f, -1.67f)
                    lineTo(12.0f, 12.9f)
                    close()
                }
                materialPath {
                    moveTo(15.56f, 6.55f)
                    lineTo(15.56f, 6.55f)
                    curveTo(14.38f, 8.02f, 12.0f, 7.19f, 12.0f, 5.3f)
                    verticalLineTo(3.77f)
                    curveToRelative(0.0f, -0.8f, -0.89f, -1.28f, -1.55f, -0.84f)
                    curveTo(8.12f, 4.49f, 4.0f, 7.97f, 4.0f, 13.0f)
                    curveToRelative(0.0f, 2.92f, 1.56f, 5.47f, 3.89f, 6.86f)
                    curveToRelative(-0.71f, -1.02f, -1.06f, -2.31f, -0.81f, -3.68f)
                    curveToRelative(0.19f, -1.04f, 0.75f, -1.98f, 1.51f, -2.72f)
                    lineToRelative(2.71f, -2.67f)
                    curveToRelative(0.39f, -0.38f, 1.01f, -0.38f, 1.4f, 0.0f)
                    lineToRelative(2.73f, 2.69f)
                    curveToRelative(0.74f, 0.73f, 1.3f, 1.65f, 1.48f, 2.68f)
                    curveToRelative(0.25f, 1.36f, -0.07f, 2.64f, -0.77f, 3.66f)
                    curveToRelative(1.89f, -1.15f, 3.29f, -3.06f, 3.71f, -5.3f)
                    curveToRelative(0.61f, -3.27f, -0.81f, -6.37f, -3.22f, -8.1f)
                    curveTo(16.3f, 6.17f, 15.83f, 6.22f, 15.56f, 6.55f)
                    close()
                }
            }
        }

        val Check: ImageVector by lazy {
            icon("Rounded.Check", autoMirror = false) {
                materialPath {
                    moveTo(9.0f, 16.17f)
                    lineTo(5.53f, 12.7f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    curveToRelative(-0.39f, 0.39f, -0.39f, 1.02f, 0.0f, 1.41f)
                    lineToRelative(4.18f, 4.18f)
                    curveToRelative(0.39f, 0.39f, 1.02f, 0.39f, 1.41f, 0.0f)
                    lineTo(20.29f, 7.71f)
                    curveToRelative(0.39f, -0.39f, 0.39f, -1.02f, 0.0f, -1.41f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    lineTo(9.0f, 16.17f)
                    close()
                }
            }
        }

        val Flag: ImageVector by lazy {
            icon("Rounded.Flag", autoMirror = false) {
                materialPath {
                    moveTo(14.4f, 6.0f)
                    lineToRelative(-0.24f, -1.2f)
                    curveToRelative(-0.09f, -0.46f, -0.5f, -0.8f, -0.98f, -0.8f)
                    horizontalLineTo(6.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(15.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineToRelative(-6.0f)
                    horizontalLineToRelative(5.6f)
                    lineToRelative(0.24f, 1.2f)
                    curveToRelative(0.09f, 0.47f, 0.5f, 0.8f, 0.98f, 0.8f)
                    horizontalLineTo(19.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineTo(7.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineToRelative(-4.6f)
                    close()
                }
            }
        }

        val WbTwilight: ImageVector by lazy {
            icon("Rounded.WbTwilight", autoMirror = false) {
                materialPath {
                    moveTo(19.07f, 9.37f)
                    lineToRelative(0.71f, -0.71f)
                    curveToRelative(0.39f, -0.39f, 0.39f, -1.02f, 0.0f, -1.41f)
                    lineToRelative(0.0f, 0.0f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    lineToRelative(-0.71f, 0.71f)
                    curveToRelative(-0.39f, 0.39f, -0.39f, 1.02f, 0.0f, 1.41f)
                    curveTo(18.04f, 9.76f, 18.68f, 9.76f, 19.07f, 9.37f)
                    close()
                }
                materialPath {
                    moveTo(21.0f, 18.0f)
                    horizontalLineTo(3.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    reflectiveCurveToRelative(0.45f, 1.0f, 1.0f, 1.0f)
                    horizontalLineToRelative(18.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    reflectiveCurveTo(21.55f, 18.0f, 21.0f, 18.0f)
                    close()
                }
                materialPath {
                    moveTo(12.0f, 7.0f)
                    lineTo(12.0f, 7.0f)
                    curveToRelative(0.56f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineTo(5.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineToRelative(0.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(1.0f)
                    curveTo(11.0f, 6.55f, 11.45f, 7.0f, 12.0f, 7.0f)
                    close()
                }
                materialPath {
                    moveTo(4.96f, 9.34f)
                    curveToRelative(0.39f, 0.39f, 1.02f, 0.39f, 1.41f, 0.0f)
                    lineToRelative(0.0f, 0.0f)
                    curveToRelative(0.39f, -0.39f, 0.39f, -1.02f, 0.0f, -1.41f)
                    lineTo(5.66f, 7.22f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    lineToRelative(0.0f, 0.0f)
                    curveToRelative(-0.39f, 0.39f, -0.39f, 1.02f, 0.0f, 1.41f)
                    lineTo(4.96f, 9.34f)
                    close()
                }
                materialPath {
                    moveTo(19.0f, 16.0f)
                    curveToRelative(0.0f, -3.87f, -3.13f, -7.0f, -7.0f, -7.0f)
                    reflectiveCurveToRelative(-7.0f, 3.13f, -7.0f, 7.0f)
                    horizontalLineTo(19.0f)
                    close()
                }
            }
        }

        val EmojiEvents: ImageVector by lazy {
            icon("Rounded.EmojiEvents", autoMirror = false) {
                materialPath {
                    moveTo(19.0f, 5.0f)
                    horizontalLineToRelative(-2.0f)
                    verticalLineTo(4.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineTo(8.0f)
                    curveTo(7.45f, 3.0f, 7.0f, 3.45f, 7.0f, 4.0f)
                    verticalLineToRelative(1.0f)
                    horizontalLineTo(5.0f)
                    curveTo(3.9f, 5.0f, 3.0f, 5.9f, 3.0f, 7.0f)
                    verticalLineToRelative(1.0f)
                    curveToRelative(0.0f, 2.55f, 1.92f, 4.63f, 4.39f, 4.94f)
                    curveToRelative(0.63f, 1.5f, 1.98f, 2.63f, 3.61f, 2.96f)
                    verticalLineTo(19.0f)
                    horizontalLineTo(8.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    verticalLineToRelative(0.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    horizontalLineToRelative(8.0f)
                    curveToRelative(0.55f, 0.0f, 1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineToRelative(0.0f)
                    curveToRelative(0.0f, -0.55f, -0.45f, -1.0f, -1.0f, -1.0f)
                    horizontalLineToRelative(-3.0f)
                    verticalLineToRelative(-3.1f)
                    curveToRelative(1.63f, -0.33f, 2.98f, -1.46f, 3.61f, -2.96f)
                    curveTo(19.08f, 12.63f, 21.0f, 10.55f, 21.0f, 8.0f)
                    verticalLineTo(7.0f)
                    curveTo(21.0f, 5.9f, 20.1f, 5.0f, 19.0f, 5.0f)
                    close()
                    moveTo(5.0f, 8.0f)
                    verticalLineTo(7.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineToRelative(3.82f)
                    curveTo(5.84f, 10.4f, 5.0f, 9.3f, 5.0f, 8.0f)
                    close()
                    moveTo(19.0f, 8.0f)
                    curveToRelative(0.0f, 1.3f, -0.84f, 2.4f, -2.0f, 2.82f)
                    verticalLineTo(7.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineTo(8.0f)
                    close()
                }
            }
        }

        val Verified: ImageVector by lazy {
            icon("Rounded.Verified", autoMirror = false) {
                materialPath {
                    moveTo(23.0f, 12.0f)
                    lineToRelative(-2.44f, -2.79f)
                    lineToRelative(0.34f, -3.69f)
                    lineToRelative(-3.61f, -0.82f)
                    lineTo(15.4f, 1.5f)
                    lineTo(12.0f, 2.96f)
                    lineTo(8.6f, 1.5f)
                    lineTo(6.71f, 4.69f)
                    lineTo(3.1f, 5.5f)
                    lineTo(3.44f, 9.2f)
                    lineTo(1.0f, 12.0f)
                    lineToRelative(2.44f, 2.79f)
                    lineToRelative(-0.34f, 3.7f)
                    lineToRelative(3.61f, 0.82f)
                    lineTo(8.6f, 22.5f)
                    lineToRelative(3.4f, -1.47f)
                    lineToRelative(3.4f, 1.46f)
                    lineToRelative(1.89f, -3.19f)
                    lineToRelative(3.61f, -0.82f)
                    lineToRelative(-0.34f, -3.69f)
                    lineTo(23.0f, 12.0f)
                    close()
                    moveTo(9.38f, 16.01f)
                    lineTo(7.0f, 13.61f)
                    curveToRelative(-0.39f, -0.39f, -0.39f, -1.02f, 0.0f, -1.41f)
                    lineToRelative(0.07f, -0.07f)
                    curveToRelative(0.39f, -0.39f, 1.03f, -0.39f, 1.42f, 0.0f)
                    lineToRelative(1.61f, 1.62f)
                    lineToRelative(5.15f, -5.16f)
                    curveToRelative(0.39f, -0.39f, 1.03f, -0.39f, 1.42f, 0.0f)
                    lineToRelative(0.07f, 0.07f)
                    curveToRelative(0.39f, 0.39f, 0.39f, 1.02f, 0.0f, 1.41f)
                    lineToRelative(-5.92f, 5.94f)
                    curveTo(10.41f, 16.4f, 9.78f, 16.4f, 9.38f, 16.01f)
                    close()
                }
            }
        }
    }

    object Outlined {
        val CalendarMonth: ImageVector by lazy {
            icon("Outlined.CalendarMonth", autoMirror = false) {
                materialPath {
                    moveTo(19.0f, 4.0f)
                    horizontalLineToRelative(-1.0f)
                    verticalLineTo(2.0f)
                    horizontalLineToRelative(-2.0f)
                    verticalLineToRelative(2.0f)
                    horizontalLineTo(8.0f)
                    verticalLineTo(2.0f)
                    horizontalLineTo(6.0f)
                    verticalLineToRelative(2.0f)
                    horizontalLineTo(5.0f)
                    curveTo(3.89f, 4.0f, 3.01f, 4.9f, 3.01f, 6.0f)
                    lineTo(3.0f, 20.0f)
                    curveToRelative(0.0f, 1.1f, 0.89f, 2.0f, 2.0f, 2.0f)
                    horizontalLineToRelative(14.0f)
                    curveToRelative(1.1f, 0.0f, 2.0f, -0.9f, 2.0f, -2.0f)
                    verticalLineTo(6.0f)
                    curveTo(21.0f, 4.9f, 20.1f, 4.0f, 19.0f, 4.0f)
                    close()
                    moveTo(19.0f, 20.0f)
                    horizontalLineTo(5.0f)
                    verticalLineTo(10.0f)
                    horizontalLineToRelative(14.0f)
                    verticalLineTo(20.0f)
                    close()
                    moveTo(19.0f, 8.0f)
                    horizontalLineTo(5.0f)
                    verticalLineTo(6.0f)
                    horizontalLineToRelative(14.0f)
                    verticalLineTo(8.0f)
                    close()
                    moveTo(9.0f, 14.0f)
                    horizontalLineTo(7.0f)
                    verticalLineToRelative(-2.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineTo(14.0f)
                    close()
                    moveTo(13.0f, 14.0f)
                    horizontalLineToRelative(-2.0f)
                    verticalLineToRelative(-2.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineTo(14.0f)
                    close()
                    moveTo(17.0f, 14.0f)
                    horizontalLineToRelative(-2.0f)
                    verticalLineToRelative(-2.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineTo(14.0f)
                    close()
                    moveTo(9.0f, 18.0f)
                    horizontalLineTo(7.0f)
                    verticalLineToRelative(-2.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineTo(18.0f)
                    close()
                    moveTo(13.0f, 18.0f)
                    horizontalLineToRelative(-2.0f)
                    verticalLineToRelative(-2.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineTo(18.0f)
                    close()
                    moveTo(17.0f, 18.0f)
                    horizontalLineToRelative(-2.0f)
                    verticalLineToRelative(-2.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineTo(18.0f)
                    close()
                }
            }
        }

        val CheckCircle: ImageVector by lazy {
            icon("Outlined.CheckCircle", autoMirror = false) {
                materialPath {
                    moveTo(12.0f, 2.0f)
                    curveTo(6.48f, 2.0f, 2.0f, 6.48f, 2.0f, 12.0f)
                    reflectiveCurveToRelative(4.48f, 10.0f, 10.0f, 10.0f)
                    reflectiveCurveToRelative(10.0f, -4.48f, 10.0f, -10.0f)
                    reflectiveCurveTo(17.52f, 2.0f, 12.0f, 2.0f)
                    close()
                    moveTo(12.0f, 20.0f)
                    curveToRelative(-4.41f, 0.0f, -8.0f, -3.59f, -8.0f, -8.0f)
                    reflectiveCurveToRelative(3.59f, -8.0f, 8.0f, -8.0f)
                    reflectiveCurveToRelative(8.0f, 3.59f, 8.0f, 8.0f)
                    reflectiveCurveToRelative(-3.59f, 8.0f, -8.0f, 8.0f)
                    close()
                    moveTo(16.59f, 7.58f)
                    lineTo(10.0f, 14.17f)
                    lineToRelative(-2.59f, -2.58f)
                    lineTo(6.0f, 13.0f)
                    lineToRelative(4.0f, 4.0f)
                    lineToRelative(8.0f, -8.0f)
                    close()
                }
            }
        }

        val Insights: ImageVector by lazy {
            icon("Outlined.Insights", autoMirror = false) {
                materialPath {
                    moveTo(21.0f, 8.0f)
                    curveToRelative(-1.45f, 0.0f, -2.26f, 1.44f, -1.93f, 2.51f)
                    lineToRelative(-3.55f, 3.56f)
                    curveToRelative(-0.3f, -0.09f, -0.74f, -0.09f, -1.04f, 0.0f)
                    lineToRelative(-2.55f, -2.55f)
                    curveTo(12.27f, 10.45f, 11.46f, 9.0f, 10.0f, 9.0f)
                    curveToRelative(-1.45f, 0.0f, -2.27f, 1.44f, -1.93f, 2.52f)
                    lineToRelative(-4.56f, 4.55f)
                    curveTo(2.44f, 15.74f, 1.0f, 16.55f, 1.0f, 18.0f)
                    curveToRelative(0.0f, 1.1f, 0.9f, 2.0f, 2.0f, 2.0f)
                    curveToRelative(1.45f, 0.0f, 2.26f, -1.44f, 1.93f, -2.51f)
                    lineToRelative(4.55f, -4.56f)
                    curveToRelative(0.3f, 0.09f, 0.74f, 0.09f, 1.04f, 0.0f)
                    lineToRelative(2.55f, 2.55f)
                    curveTo(12.73f, 16.55f, 13.54f, 18.0f, 15.0f, 18.0f)
                    curveToRelative(1.45f, 0.0f, 2.27f, -1.44f, 1.93f, -2.52f)
                    lineToRelative(3.56f, -3.55f)
                    curveTo(21.56f, 12.26f, 23.0f, 11.45f, 23.0f, 10.0f)
                    curveTo(23.0f, 8.9f, 22.1f, 8.0f, 21.0f, 8.0f)
                    close()
                }
                materialPath {
                    moveTo(15.0f, 9.0f)
                    lineToRelative(0.94f, -2.07f)
                    lineToRelative(2.06f, -0.93f)
                    lineToRelative(-2.06f, -0.93f)
                    lineToRelative(-0.94f, -2.07f)
                    lineToRelative(-0.92f, 2.07f)
                    lineToRelative(-2.08f, 0.93f)
                    lineToRelative(2.08f, 0.93f)
                    close()
                }
                materialPath {
                    moveTo(3.5f, 11.0f)
                    lineToRelative(0.5f, -2.0f)
                    lineToRelative(2.0f, -0.5f)
                    lineToRelative(-2.0f, -0.5f)
                    lineToRelative(-0.5f, -2.0f)
                    lineToRelative(-0.5f, 2.0f)
                    lineToRelative(-2.0f, 0.5f)
                    lineToRelative(2.0f, 0.5f)
                    close()
                }
            }
        }

        val Settings: ImageVector by lazy {
            icon("Outlined.Settings", autoMirror = false) {
                materialPath {
                    moveTo(19.43f, 12.98f)
                    curveToRelative(0.04f, -0.32f, 0.07f, -0.64f, 0.07f, -0.98f)
                    curveToRelative(0.0f, -0.34f, -0.03f, -0.66f, -0.07f, -0.98f)
                    lineToRelative(2.11f, -1.65f)
                    curveToRelative(0.19f, -0.15f, 0.24f, -0.42f, 0.12f, -0.64f)
                    lineToRelative(-2.0f, -3.46f)
                    curveToRelative(-0.09f, -0.16f, -0.26f, -0.25f, -0.44f, -0.25f)
                    curveToRelative(-0.06f, 0.0f, -0.12f, 0.01f, -0.17f, 0.03f)
                    lineToRelative(-2.49f, 1.0f)
                    curveToRelative(-0.52f, -0.4f, -1.08f, -0.73f, -1.69f, -0.98f)
                    lineToRelative(-0.38f, -2.65f)
                    curveTo(14.46f, 2.18f, 14.25f, 2.0f, 14.0f, 2.0f)
                    horizontalLineToRelative(-4.0f)
                    curveToRelative(-0.25f, 0.0f, -0.46f, 0.18f, -0.49f, 0.42f)
                    lineToRelative(-0.38f, 2.65f)
                    curveToRelative(-0.61f, 0.25f, -1.17f, 0.59f, -1.69f, 0.98f)
                    lineToRelative(-2.49f, -1.0f)
                    curveToRelative(-0.06f, -0.02f, -0.12f, -0.03f, -0.18f, -0.03f)
                    curveToRelative(-0.17f, 0.0f, -0.34f, 0.09f, -0.43f, 0.25f)
                    lineToRelative(-2.0f, 3.46f)
                    curveToRelative(-0.13f, 0.22f, -0.07f, 0.49f, 0.12f, 0.64f)
                    lineToRelative(2.11f, 1.65f)
                    curveToRelative(-0.04f, 0.32f, -0.07f, 0.65f, -0.07f, 0.98f)
                    curveToRelative(0.0f, 0.33f, 0.03f, 0.66f, 0.07f, 0.98f)
                    lineToRelative(-2.11f, 1.65f)
                    curveToRelative(-0.19f, 0.15f, -0.24f, 0.42f, -0.12f, 0.64f)
                    lineToRelative(2.0f, 3.46f)
                    curveToRelative(0.09f, 0.16f, 0.26f, 0.25f, 0.44f, 0.25f)
                    curveToRelative(0.06f, 0.0f, 0.12f, -0.01f, 0.17f, -0.03f)
                    lineToRelative(2.49f, -1.0f)
                    curveToRelative(0.52f, 0.4f, 1.08f, 0.73f, 1.69f, 0.98f)
                    lineToRelative(0.38f, 2.65f)
                    curveToRelative(0.03f, 0.24f, 0.24f, 0.42f, 0.49f, 0.42f)
                    horizontalLineToRelative(4.0f)
                    curveToRelative(0.25f, 0.0f, 0.46f, -0.18f, 0.49f, -0.42f)
                    lineToRelative(0.38f, -2.65f)
                    curveToRelative(0.61f, -0.25f, 1.17f, -0.59f, 1.69f, -0.98f)
                    lineToRelative(2.49f, 1.0f)
                    curveToRelative(0.06f, 0.02f, 0.12f, 0.03f, 0.18f, 0.03f)
                    curveToRelative(0.17f, 0.0f, 0.34f, -0.09f, 0.43f, -0.25f)
                    lineToRelative(2.0f, -3.46f)
                    curveToRelative(0.12f, -0.22f, 0.07f, -0.49f, -0.12f, -0.64f)
                    lineToRelative(-2.11f, -1.65f)
                    close()
                    moveTo(17.45f, 11.27f)
                    curveToRelative(0.04f, 0.31f, 0.05f, 0.52f, 0.05f, 0.73f)
                    curveToRelative(0.0f, 0.21f, -0.02f, 0.43f, -0.05f, 0.73f)
                    lineToRelative(-0.14f, 1.13f)
                    lineToRelative(0.89f, 0.7f)
                    lineToRelative(1.08f, 0.84f)
                    lineToRelative(-0.7f, 1.21f)
                    lineToRelative(-1.27f, -0.51f)
                    lineToRelative(-1.04f, -0.42f)
                    lineToRelative(-0.9f, 0.68f)
                    curveToRelative(-0.43f, 0.32f, -0.84f, 0.56f, -1.25f, 0.73f)
                    lineToRelative(-1.06f, 0.43f)
                    lineToRelative(-0.16f, 1.13f)
                    lineToRelative(-0.2f, 1.35f)
                    horizontalLineToRelative(-1.4f)
                    lineToRelative(-0.19f, -1.35f)
                    lineToRelative(-0.16f, -1.13f)
                    lineToRelative(-1.06f, -0.43f)
                    curveToRelative(-0.43f, -0.18f, -0.83f, -0.41f, -1.23f, -0.71f)
                    lineToRelative(-0.91f, -0.7f)
                    lineToRelative(-1.06f, 0.43f)
                    lineToRelative(-1.27f, 0.51f)
                    lineToRelative(-0.7f, -1.21f)
                    lineToRelative(1.08f, -0.84f)
                    lineToRelative(0.89f, -0.7f)
                    lineToRelative(-0.14f, -1.13f)
                    curveToRelative(-0.03f, -0.31f, -0.05f, -0.54f, -0.05f, -0.74f)
                    reflectiveCurveToRelative(0.02f, -0.43f, 0.05f, -0.73f)
                    lineToRelative(0.14f, -1.13f)
                    lineToRelative(-0.89f, -0.7f)
                    lineToRelative(-1.08f, -0.84f)
                    lineToRelative(0.7f, -1.21f)
                    lineToRelative(1.27f, 0.51f)
                    lineToRelative(1.04f, 0.42f)
                    lineToRelative(0.9f, -0.68f)
                    curveToRelative(0.43f, -0.32f, 0.84f, -0.56f, 1.25f, -0.73f)
                    lineToRelative(1.06f, -0.43f)
                    lineToRelative(0.16f, -1.13f)
                    lineToRelative(0.2f, -1.35f)
                    horizontalLineToRelative(1.39f)
                    lineToRelative(0.19f, 1.35f)
                    lineToRelative(0.16f, 1.13f)
                    lineToRelative(1.06f, 0.43f)
                    curveToRelative(0.43f, 0.18f, 0.83f, 0.41f, 1.23f, 0.71f)
                    lineToRelative(0.91f, 0.7f)
                    lineToRelative(1.06f, -0.43f)
                    lineToRelative(1.27f, -0.51f)
                    lineToRelative(0.7f, 1.21f)
                    lineToRelative(-1.07f, 0.85f)
                    lineToRelative(-0.89f, 0.7f)
                    lineToRelative(0.14f, 1.13f)
                    close()
                    moveTo(12.0f, 8.0f)
                    curveToRelative(-2.21f, 0.0f, -4.0f, 1.79f, -4.0f, 4.0f)
                    reflectiveCurveToRelative(1.79f, 4.0f, 4.0f, 4.0f)
                    reflectiveCurveToRelative(4.0f, -1.79f, 4.0f, -4.0f)
                    reflectiveCurveToRelative(-1.79f, -4.0f, -4.0f, -4.0f)
                    close()
                    moveTo(12.0f, 14.0f)
                    curveToRelative(-1.1f, 0.0f, -2.0f, -0.9f, -2.0f, -2.0f)
                    reflectiveCurveToRelative(0.9f, -2.0f, 2.0f, -2.0f)
                    reflectiveCurveToRelative(2.0f, 0.9f, 2.0f, 2.0f)
                    reflectiveCurveToRelative(-0.9f, 2.0f, -2.0f, 2.0f)
                    close()
                }
            }
        }

        val Info: ImageVector by lazy {
            icon("Outlined.Info", autoMirror = false) {
                materialPath {
                    moveTo(11.0f, 7.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineToRelative(2.0f)
                    horizontalLineToRelative(-2.0f)
                    close()
                    moveTo(11.0f, 11.0f)
                    horizontalLineToRelative(2.0f)
                    verticalLineToRelative(6.0f)
                    horizontalLineToRelative(-2.0f)
                    close()
                    moveTo(12.0f, 2.0f)
                    curveTo(6.48f, 2.0f, 2.0f, 6.48f, 2.0f, 12.0f)
                    reflectiveCurveToRelative(4.48f, 10.0f, 10.0f, 10.0f)
                    reflectiveCurveToRelative(10.0f, -4.48f, 10.0f, -10.0f)
                    reflectiveCurveTo(17.52f, 2.0f, 12.0f, 2.0f)
                    close()
                    moveTo(12.0f, 20.0f)
                    curveToRelative(-4.41f, 0.0f, -8.0f, -3.59f, -8.0f, -8.0f)
                    reflectiveCurveToRelative(3.59f, -8.0f, 8.0f, -8.0f)
                    reflectiveCurveToRelative(8.0f, 3.59f, 8.0f, 8.0f)
                    reflectiveCurveToRelative(-3.59f, 8.0f, -8.0f, 8.0f)
                    close()
                }
            }
        }
    }

    object AutoMirroredRounded {
        val DirectionsRun: ImageVector by lazy {
            icon("AutoMirrored.Rounded.DirectionsRun", autoMirror = true) {
                materialPath {
                    moveTo(13.49f, 5.48f)
                    curveToRelative(1.1f, 0.0f, 2.0f, -0.9f, 2.0f, -2.0f)
                    reflectiveCurveToRelative(-0.9f, -2.0f, -2.0f, -2.0f)
                    reflectiveCurveToRelative(-2.0f, 0.9f, -2.0f, 2.0f)
                    reflectiveCurveToRelative(0.9f, 2.0f, 2.0f, 2.0f)
                    close()
                    moveTo(10.32f, 17.48f)
                    lineToRelative(0.57f, -2.5f)
                    lineToRelative(2.1f, 2.0f)
                    verticalLineToRelative(5.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineToRelative(-5.64f)
                    curveToRelative(0.0f, -0.55f, -0.22f, -1.07f, -0.62f, -1.45f)
                    lineToRelative(-1.48f, -1.41f)
                    lineToRelative(0.6f, -3.0f)
                    curveToRelative(1.07f, 1.24f, 2.62f, 2.13f, 4.36f, 2.41f)
                    curveToRelative(0.6f, 0.09f, 1.14f, -0.39f, 1.14f, -1.0f)
                    curveToRelative(0.0f, -0.49f, -0.36f, -0.9f, -0.85f, -0.98f)
                    curveToRelative(-1.52f, -0.25f, -2.78f, -1.15f, -3.45f, -2.33f)
                    lineToRelative(-1.0f, -1.6f)
                    curveToRelative(-0.4f, -0.6f, -1.0f, -1.0f, -1.7f, -1.0f)
                    curveToRelative(-0.3f, 0.0f, -0.5f, 0.1f, -0.8f, 0.1f)
                    lineTo(7.21f, 7.76f)
                    curveToRelative(-0.74f, 0.32f, -1.22f, 1.04f, -1.22f, 1.85f)
                    verticalLineToRelative(2.37f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    reflectiveCurveToRelative(1.0f, -0.45f, 1.0f, -1.0f)
                    verticalLineToRelative(-2.4f)
                    lineToRelative(1.8f, -0.7f)
                    lineToRelative(-1.6f, 8.1f)
                    lineToRelative(-3.92f, -0.8f)
                    curveToRelative(-0.54f, -0.11f, -1.07f, 0.24f, -1.18f, 0.78f)
                    lineTo(3.09f, 17.0f)
                    curveToRelative(-0.11f, 0.54f, 0.24f, 1.07f, 0.78f, 1.18f)
                    lineToRelative(4.11f, 0.82f)
                    curveToRelative(1.06f, 0.21f, 2.1f, -0.46f, 2.34f, -1.52f)
                    close()
                }
            }
        }

        val MenuBook: ImageVector by lazy {
            icon("AutoMirrored.Rounded.MenuBook", autoMirror = true) {
                materialPath {
                    moveTo(17.5f, 4.5f)
                    curveToRelative(-1.95f, 0.0f, -4.05f, 0.4f, -5.5f, 1.5f)
                    curveToRelative(-1.45f, -1.1f, -3.55f, -1.5f, -5.5f, -1.5f)
                    curveToRelative(-1.45f, 0.0f, -2.99f, 0.22f, -4.28f, 0.79f)
                    curveTo(1.49f, 5.62f, 1.0f, 6.33f, 1.0f, 7.14f)
                    lineToRelative(0.0f, 11.28f)
                    curveToRelative(0.0f, 1.3f, 1.22f, 2.26f, 2.48f, 1.94f)
                    curveTo(4.46f, 20.11f, 5.5f, 20.0f, 6.5f, 20.0f)
                    curveToRelative(1.56f, 0.0f, 3.22f, 0.26f, 4.56f, 0.92f)
                    curveToRelative(0.6f, 0.3f, 1.28f, 0.3f, 1.87f, 0.0f)
                    curveToRelative(1.34f, -0.67f, 3.0f, -0.92f, 4.56f, -0.92f)
                    curveToRelative(1.0f, 0.0f, 2.04f, 0.11f, 3.02f, 0.36f)
                    curveToRelative(1.26f, 0.33f, 2.48f, -0.63f, 2.48f, -1.94f)
                    lineToRelative(0.0f, -11.28f)
                    curveToRelative(0.0f, -0.81f, -0.49f, -1.52f, -1.22f, -1.85f)
                    curveTo(20.49f, 4.72f, 18.95f, 4.5f, 17.5f, 4.5f)
                    close()
                    moveTo(21.0f, 17.23f)
                    curveToRelative(0.0f, 0.63f, -0.58f, 1.09f, -1.2f, 0.98f)
                    curveToRelative(-0.75f, -0.14f, -1.53f, -0.2f, -2.3f, -0.2f)
                    curveToRelative(-1.7f, 0.0f, -4.15f, 0.65f, -5.5f, 1.5f)
                    verticalLineTo(8.0f)
                    curveToRelative(1.35f, -0.85f, 3.8f, -1.5f, 5.5f, -1.5f)
                    curveToRelative(0.92f, 0.0f, 1.83f, 0.09f, 2.7f, 0.28f)
                    curveToRelative(0.46f, 0.1f, 0.8f, 0.51f, 0.8f, 0.98f)
                    verticalLineTo(17.23f)
                    close()
                }
                materialPath {
                    moveTo(13.98f, 11.01f)
                    curveToRelative(-0.32f, 0.0f, -0.61f, -0.2f, -0.71f, -0.52f)
                    curveToRelative(-0.13f, -0.39f, 0.09f, -0.82f, 0.48f, -0.94f)
                    curveToRelative(1.54f, -0.5f, 3.53f, -0.66f, 5.36f, -0.45f)
                    curveToRelative(0.41f, 0.05f, 0.71f, 0.42f, 0.66f, 0.83f)
                    curveToRelative(-0.05f, 0.41f, -0.42f, 0.71f, -0.83f, 0.66f)
                    curveToRelative(-1.62f, -0.19f, -3.39f, -0.04f, -4.73f, 0.39f)
                    curveTo(14.13f, 10.99f, 14.05f, 11.01f, 13.98f, 11.01f)
                    close()
                }
                materialPath {
                    moveTo(13.98f, 13.67f)
                    curveToRelative(-0.32f, 0.0f, -0.61f, -0.2f, -0.71f, -0.52f)
                    curveToRelative(-0.13f, -0.39f, 0.09f, -0.82f, 0.48f, -0.94f)
                    curveToRelative(1.53f, -0.5f, 3.53f, -0.66f, 5.36f, -0.45f)
                    curveToRelative(0.41f, 0.05f, 0.71f, 0.42f, 0.66f, 0.83f)
                    curveToRelative(-0.05f, 0.41f, -0.42f, 0.71f, -0.83f, 0.66f)
                    curveToRelative(-1.62f, -0.19f, -3.39f, -0.04f, -4.73f, 0.39f)
                    curveTo(14.13f, 13.66f, 14.05f, 13.67f, 13.98f, 13.67f)
                    close()
                }
                materialPath {
                    moveTo(13.98f, 16.33f)
                    curveToRelative(-0.32f, 0.0f, -0.61f, -0.2f, -0.71f, -0.52f)
                    curveToRelative(-0.13f, -0.39f, 0.09f, -0.82f, 0.48f, -0.94f)
                    curveToRelative(1.53f, -0.5f, 3.53f, -0.66f, 5.36f, -0.45f)
                    curveToRelative(0.41f, 0.05f, 0.71f, 0.42f, 0.66f, 0.83f)
                    curveToRelative(-0.05f, 0.41f, -0.42f, 0.7f, -0.83f, 0.66f)
                    curveToRelative(-1.62f, -0.19f, -3.39f, -0.04f, -4.73f, 0.39f)
                    curveTo(14.13f, 16.32f, 14.05f, 16.33f, 13.98f, 16.33f)
                    close()
                }
            }
        }

        val KeyboardArrowRight: ImageVector by lazy {
            icon("AutoMirrored.Rounded.KeyboardArrowRight", autoMirror = true) {
                materialPath {
                    moveTo(9.29f, 15.88f)
                    lineTo(13.17f, 12.0f)
                    lineTo(9.29f, 8.12f)
                    curveToRelative(-0.39f, -0.39f, -0.39f, -1.02f, 0.0f, -1.41f)
                    curveToRelative(0.39f, -0.39f, 1.02f, -0.39f, 1.41f, 0.0f)
                    lineToRelative(4.59f, 4.59f)
                    curveToRelative(0.39f, 0.39f, 0.39f, 1.02f, 0.0f, 1.41f)
                    lineTo(10.7f, 17.3f)
                    curveToRelative(-0.39f, 0.39f, -1.02f, 0.39f, -1.41f, 0.0f)
                    curveToRelative(-0.38f, -0.39f, -0.39f, -1.03f, 0.0f, -1.42f)
                    close()
                }
            }
        }

        val VolumeUp: ImageVector by lazy {
            icon("AutoMirrored.Rounded.VolumeUp", autoMirror = true) {
                materialPath {
                    moveTo(3.0f, 10.0f)
                    verticalLineToRelative(4.0f)
                    curveToRelative(0.0f, 0.55f, 0.45f, 1.0f, 1.0f, 1.0f)
                    horizontalLineToRelative(3.0f)
                    lineToRelative(3.29f, 3.29f)
                    curveToRelative(0.63f, 0.63f, 1.71f, 0.18f, 1.71f, -0.71f)
                    lineTo(12.0f, 6.41f)
                    curveToRelative(0.0f, -0.89f, -1.08f, -1.34f, -1.71f, -0.71f)
                    lineTo(7.0f, 9.0f)
                    lineTo(4.0f, 9.0f)
                    curveToRelative(-0.55f, 0.0f, -1.0f, 0.45f, -1.0f, 1.0f)
                    close()
                    moveTo(16.5f, 12.0f)
                    curveToRelative(0.0f, -1.77f, -1.02f, -3.29f, -2.5f, -4.03f)
                    verticalLineToRelative(8.05f)
                    curveToRelative(1.48f, -0.73f, 2.5f, -2.25f, 2.5f, -4.02f)
                    close()
                    moveTo(14.0f, 4.45f)
                    verticalLineToRelative(0.2f)
                    curveToRelative(0.0f, 0.38f, 0.25f, 0.71f, 0.6f, 0.85f)
                    curveTo(17.18f, 6.53f, 19.0f, 9.06f, 19.0f, 12.0f)
                    reflectiveCurveToRelative(-1.82f, 5.47f, -4.4f, 6.5f)
                    curveToRelative(-0.36f, 0.14f, -0.6f, 0.47f, -0.6f, 0.85f)
                    verticalLineToRelative(0.2f)
                    curveToRelative(0.0f, 0.63f, 0.63f, 1.07f, 1.21f, 0.85f)
                    curveTo(18.6f, 19.11f, 21.0f, 15.84f, 21.0f, 12.0f)
                    reflectiveCurveToRelative(-2.4f, -7.11f, -5.79f, -8.4f)
                    curveToRelative(-0.58f, -0.23f, -1.21f, 0.22f, -1.21f, 0.85f)
                    close()
                }
            }
        }

        val TrendingUp: ImageVector by lazy {
            icon("AutoMirrored.Rounded.TrendingUp", autoMirror = true) {
                materialPath {
                    moveTo(16.85f, 6.85f)
                    lineToRelative(1.44f, 1.44f)
                    lineToRelative(-4.88f, 4.88f)
                    lineToRelative(-3.29f, -3.29f)
                    curveToRelative(-0.39f, -0.39f, -1.02f, -0.39f, -1.41f, 0.0f)
                    lineToRelative(-6.0f, 6.01f)
                    curveToRelative(-0.39f, 0.39f, -0.39f, 1.02f, 0.0f, 1.41f)
                    curveToRelative(0.39f, 0.39f, 1.02f, 0.39f, 1.41f, 0.0f)
                    lineTo(9.41f, 12.0f)
                    lineToRelative(3.29f, 3.29f)
                    curveToRelative(0.39f, 0.39f, 1.02f, 0.39f, 1.41f, 0.0f)
                    lineToRelative(5.59f, -5.58f)
                    lineToRelative(1.44f, 1.44f)
                    curveToRelative(0.31f, 0.31f, 0.85f, 0.09f, 0.85f, -0.35f)
                    verticalLineTo(6.5f)
                    curveToRelative(0.01f, -0.28f, -0.21f, -0.5f, -0.49f, -0.5f)
                    horizontalLineToRelative(-4.29f)
                    curveToRelative(-0.45f, 0.0f, -0.67f, 0.54f, -0.36f, 0.85f)
                    close()
                }
            }
        }
    }
}
