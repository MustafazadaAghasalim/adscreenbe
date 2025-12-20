package com.example.adscreen

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.example.adscreen.ui.AdPlayer
import com.example.adscreen.ui.PlaylistViewModel
import dagger.hilt.android.AndroidEntryPoint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.graphicsLayer

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private lateinit var telemetryManager: TelemetryManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        telemetryManager = TelemetryManager(this)

        // Hide System UI for Kiosk Mode
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        val windowInsetsController = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        windowInsetsController.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())

        // Request Permissions & Start Telemetry
        val locationPermissionRequest = registerForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions()
        ) { permissions ->
            when {
                permissions.getOrDefault(android.Manifest.permission.ACCESS_FINE_LOCATION, false) -> {
                    telemetryManager.startTracking()
                }
                permissions.getOrDefault(android.Manifest.permission.ACCESS_COARSE_LOCATION, false) -> {
                    telemetryManager.startTracking()
                }
                else -> {
                    // No location access granted.
                }
            }
        }

        locationPermissionRequest.launch(arrayOf(
            android.Manifest.permission.ACCESS_FINE_LOCATION,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ))

        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = Color.Black
                ) {
                    KioskScreen()
                }
            }
        }
    }
}

@Composable
fun KioskScreen(viewModel: PlaylistViewModel = hiltViewModel()) {
    val ads by viewModel.ads.collectAsState()
    val currentIndex by viewModel.currentIndex.collectAsState()
    
    // Timer state for BottomBar
    var timeMillis by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) {
        val startTime = System.currentTimeMillis()
        while (true) {
            timeMillis = System.currentTimeMillis() - startTime
            delay(1000)
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // A) Advertisement Area: 1920x1080
        // We use weight to fill available space, but user asked for specific px.
        // Screen is 1920x1200. 1080/1200 = 0.9. 120/1200 = 0.1.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(0.9f)
        ) {
            if (ads.isNotEmpty()) {
                val currentAd = ads.getOrNull(currentIndex)
                if (currentAd != null) {
                    AdPlayer(
                        ad = currentAd,
                        onFinished = { viewModel.onAdFinished() }
                    )
                }
            } else {
                // Placeholder or Loading
                 Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Loading Ads...", color = Color.White)
                 }
            }
        }

        // B) Navigation Bar: 120px
        // 120px / density approx 1.0 (mdpi) = 120dp. 
        // Need to convert px to dp properly or just use weight.
        // User said verified screen size 1920x1200.
        // .weight(0.1f) should imply the remaining ratio.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(0.1f)
                .background(Color.Black)
        ) {
             BottomBar(timeMillis)
        }
    }
}

val KinetikaFont = FontFamily(
    Font(R.font.kinetika_semi_bold, FontWeight.SemiBold)
)

enum class Screen {
    Home, Quiz, Finished
}

data class Question(
    val text: String,
    val options: List<Pair<String, String>>, // "A" to "Text"
    val correctLabel: String
)

val QuestionsList = listOf(
    // Q1 (Original)
    Question(
        text = "“Leyli və Məcnun” əsərinin müəllifi olan məşhur\norta əsr Azərbaycan şairi kimdir?",
        options = listOf(
            "A" to "Əbülhəsən Rüdəki",
            "B" to "Xaqani Şirvani", // Keeping user's original preference
            "C" to "Nizami Gəncəvi",
            "D" to "Məhəmməd Füzuli"
        ),
        correctLabel = "B"
    ),
    // Q2
    Question(
        text = "Şərq aləmində ilk operanın adı nədir?",
        options = listOf(
            "A" to "Koroğlu",
            "B" to "Leyli və Məcnun",
            "C" to "Şah İsmayı",
            "D" to "Aşıq Qərib"
        ),
        correctLabel = "B"
    ),
    // Q3
    Question(
        text = "Qız Qalası neçənci əsrdə tikilmişdir?",
        options = listOf(
            "A" to "XI əsr",
            "B" to "XII əsr",
            "C" to "VII əsr",
            "D" to "XIV əsr"
        ),
        correctLabel = "B"
    ),
    // Q4
    Question(
        text = "Azərbaycanın musiqi rəmzi hansı alət sayılır?",
        options = listOf(
            "A" to "Kamança",
            "B" to "Tar",
            "C" to "Qaval",
            "D" to "Balaban"
        ),
        correctLabel = "B"
    ),
    // Q5
    Question(
        text = "Şuşanın simvolu olan gül hansıdır?",
        options = listOf(
            "A" to "Qızılgül",
            "B" to "Xarıbülbül",
            "C" to "Yasəmən",
            "D" to "Lalə"
        ),
        correctLabel = "B"
    ),
    // Q6 (Finale)
    Question(
        text = "Əsrin müqaviləsi neçənci ildə imzulanıb?",
        options = listOf(
            "A" to "1993",
            "B" to "1994",
            "C" to "1995",
            "D" to "1996"
        ),
        correctLabel = "B"
    )
)

@Composable
fun AppNavigation() {
    var currentScreen by remember { mutableStateOf(Screen.Home) }
    var timeMillis by remember { mutableLongStateOf(0L) }
    
    // Global Timer
    LaunchedEffect(Unit) {
        val startTime = System.currentTimeMillis()
        while (true) {
            timeMillis = System.currentTimeMillis() - startTime
            delay(16)
        }
    }

    // Permission Handling and Location Logic
    val context = androidx.compose.ui.platform.LocalContext.current
    
    // Instantiate TelemetryManager (which now holds state)
    // Using simple remember to avoid recreating, but passing context is fine as it's Activity context usually.
    val telemetryManager = remember { TelemetryManager(context) }
    
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions(),
        onResult = { permissions -> 
            val isGranted = permissions[android.Manifest.permission.ACCESS_FINE_LOCATION] == true || 
                            permissions[android.Manifest.permission.ACCESS_COARSE_LOCATION] == true
            if (isGranted) {
                telemetryManager.startTracking()
            }
        }
    )

    LaunchedEffect(Unit) {
        val fineLocation = androidx.core.content.ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        )
        val coarseLocation = androidx.core.content.ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        )
        
        if (fineLocation == android.content.pm.PackageManager.PERMISSION_GRANTED || 
            coarseLocation == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            telemetryManager.startTracking()
        } else {
            permissionLauncher.launch(
                arrayOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
        }
    }

    // Auto-transition to Quiz
    LaunchedEffect(currentScreen) {
        if (currentScreen == Screen.Home) {
            delay(12000)
            currentScreen = Screen.Quiz
        }
    }

    when (currentScreen) {
        Screen.Home -> AdscreenLayout(timeMillis)
        Screen.Quiz -> QuizFlowScreen(
            timeMillis = timeMillis,
            onFailure = { currentScreen = Screen.Home },
            onFinished = { currentScreen = Screen.Finished }
        )
        Screen.Finished -> FinalSuccessScreen(
            onHome = { currentScreen = Screen.Home }
        )
    }
}

@Composable
fun AdscreenLayout(timeMillis: Long) {
    Box(modifier = Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(id = R.drawable.background),
            contentDescription = "Background",
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop
        )
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(modifier = Modifier.weight(1f))
            BottomBar(timeMillis)
        }
    }
}

@OptIn(ExperimentalAnimationApi::class)
@Composable
fun QuizFlowScreen(
    timeMillis: Long,
    onFailure: () -> Unit,
    onFinished: () -> Unit
) {
    var questionIndex by remember { mutableStateOf(0) }
    var showSuccessPopup by remember { mutableStateOf(false) }
    var showFailurePopup by remember { mutableStateOf(false) }
    
    val currentQuestion = QuestionsList.getOrNull(questionIndex)

    Box(modifier = Modifier.fillMaxSize().background(Color(0xFF1A1A40))) {
        
        // Animated Question Content
        AnimatedContent(
            targetState = currentQuestion,
            transitionSpec = {
                // Premium Slide + Scale + Fade Transition
                (slideInHorizontally(
                    animationSpec = tween(durationMillis = 600, easing = FastOutSlowInEasing)
                ) { width -> width } + 
                fadeIn(
                    animationSpec = tween(durationMillis = 600)
                ) + 
                scaleIn(
                    initialScale = 0.9f,
                    animationSpec = tween(durationMillis = 600, easing = FastOutSlowInEasing)
                )).togetherWith(
                slideOutHorizontally(
                    animationSpec = tween(durationMillis = 600, easing = FastOutSlowInEasing)
                ) { width -> -width } + 
                fadeOut(
                    animationSpec = tween(durationMillis = 600)
                ) +
                scaleOut(
                    targetScale = 1.1f, // Slight zoom out effect on exit
                    animationSpec = tween(durationMillis = 600)
                ))
            }
        ) { question ->
            if (question != null) {
                SingleQuestionLayout(
                    question = question,
                    onCorrect = { showSuccessPopup = true },
                    onWrong = { showFailurePopup = true }
                )
            }
        }
        
        // Bottom Bar persistent
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            BottomBar(timeMillis)
        }

        // Popups
        if (showSuccessPopup) {
            DialogOverlay(
                title = "Afərin!",
                message = "Sən bunu edə bilərsən!",
                buttonText = "Davam et",
                isSuccess = true,
                onButtonClick = {
                    showSuccessPopup = false
                    if (questionIndex < QuestionsList.size - 1) {
                        questionIndex++
                    } else {
                        onFinished()
                    }
                }
            )
        }

        if (showFailurePopup) {
            DialogOverlay(
                title = "Təəssüf...",
                message = "Cavab yalnışdır.",
                buttonText = "Bağla",
                isSuccess = false,
                onButtonClick = {
                    showFailurePopup = false
                    onFailure()
                }
            )
            // Auto-fail logic
            LaunchedEffect(Unit) {
                delay(3000)
                onFailure()
            }
        }
    }
}

@Composable
fun SingleQuestionLayout(
    question: Question,
    onCorrect: () -> Unit,
    onWrong: () -> Unit
) {
    // Split Layout
    Row(modifier = Modifier.fillMaxSize()) {
        // Left Side: Image
        Box(
            modifier = Modifier
                .weight(0.35f)
                .fillMaxHeight()
                .padding(24.dp),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(id = R.drawable.poll),
                contentDescription = "Quiz Image",
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(16.dp)),
                contentScale = ContentScale.Crop
            )
        }

        // Right Side: Question and Options
        Column(
            modifier = Modifier
                .weight(0.65f)
                .fillMaxHeight()
                .padding(40.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = question.text,
                color = Color.White,
                fontSize = 32.sp,
                fontFamily = KinetikaFont,
                fontWeight = FontWeight.Bold,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                lineHeight = 40.sp,
                modifier = Modifier.graphicsLayer { shadowElevation = 10f }
            )
            
            Spacer(modifier = Modifier.height(48.dp))
            
            var selectedAnswer by remember { mutableStateOf<String?>(null) }

            question.options.forEach { (label, text) ->
                QuizButton(
                    label = label,
                    text = text,
                    isSelected = selectedAnswer == label,
                    isCorrect = label == question.correctLabel,
                    isAnswered = selectedAnswer != null,
                    onClick = { 
                         if (selectedAnswer == null) {
                             selectedAnswer = label
                             if (label == question.correctLabel) {
                                 onCorrect()
                             } else {
                                 onWrong()
                             }
                         }
                    }
                )
                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

@Composable
fun FinalSuccessScreen(onHome: () -> Unit) {
    // Auto-home
    LaunchedEffect(Unit) {
        delay(5000)
        onHome()
    }
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.radialGradient(listOf(Color(0xFFFFD700), Color(0xFF6200EA), Color.Black)))
            .clickable { onHome() },
        contentAlignment = Alignment.Center
    ) {
        // Animated content for Final Screen
        var visible by remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { visible = true }

        AnimatedVisibility(
            visible = visible,
            enter = scaleIn(animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy)) + fadeIn(),
            exit = fadeOut()
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = "🎉", fontSize = 120.sp)
                Spacer(modifier = Modifier.height(32.dp))
                Text(
                    text = "Təbriklər!",
                     color = Color.White,
                    fontSize = 64.sp,
                    fontFamily = KinetikaFont,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Siz bütün suallara düzgün cavab verdiniz!",
                    color = Color.White,
                    fontSize = 32.sp,
                    fontFamily = KinetikaFont
                )
            }
        }
    }
}

@Composable
fun DialogOverlay(
    title: String,
    message: String,
    buttonText: String,
    isSuccess: Boolean,
    onButtonClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.8f))
            .clickable(enabled = false) {}, 
        contentAlignment = Alignment.Center
    ) {
        // Pop-up Animation with Spring Physics
        var visible by remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { visible = true }
        
        AnimatedVisibility(
            visible = visible,
            enter = scaleIn(
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioMediumBouncy,
                    stiffness = Spring.StiffnessLow
                )
            ) + fadeIn(),
            exit = scaleOut(animationSpec = tween(durationMillis = 200)) + fadeOut()
        ) {
            Column(
                modifier = Modifier
                    .width(400.dp)
                    .background(Color(0xFF222222), RoundedCornerShape(16.dp))
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = title,
                    color = if (isSuccess) Color.Green else Color.Red,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = KinetikaFont
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = message,
                    color = Color.White,
                    fontSize = 20.sp,
                    fontFamily = KinetikaFont,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
                Spacer(modifier = Modifier.height(32.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp)
                        .background(
                            if (isSuccess) Color(0xFFFF9900) else Color.Gray, 
                            RoundedCornerShape(8.dp)
                        )
                        .clickable { onButtonClick() },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = buttonText,
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = KinetikaFont
                    )
                }
            }
        }
    }
}

@Composable
fun QuizButton(
    label: String,
    text: String,
    isSelected: Boolean,
    isCorrect: Boolean,
    isAnswered: Boolean,
    onClick: () -> Unit
) {
    // Animations
    val scale by androidx.compose.animation.core.animateFloatAsState(
        targetValue = if (isSelected) 1.05f else 1f,
        label = "scale",
        animationSpec = spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessLow) // Bouncy button
    )

    val backgroundColor by androidx.compose.animation.animateColorAsState(
        targetValue = when {
            isSelected && isCorrect -> Color.Green.copy(alpha = 0.3f)
            isSelected && !isCorrect -> Color.Red.copy(alpha = 0.3f)
            else -> Color.Transparent
        }, 
        label = "bg",
        animationSpec = tween(durationMillis = 300)
    )
    
    val borderColor by androidx.compose.animation.animateColorAsState(
        targetValue = when {
             isSelected && isCorrect -> Color.Green
             isSelected && !isCorrect -> Color.Red
             isAnswered && isCorrect && !isSelected -> Color.Green.copy(alpha = 0.5f) 
             else -> Color.White
        },
        label = "border",
        animationSpec = tween(durationMillis = 300)
    )

    // Custom Hexagon/Arrow Shape
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(70.dp)
            .padding(horizontal = 40.dp)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clickable(enabled = !isAnswered) { onClick() }
    ) {
         Canvas(modifier = Modifier.fillMaxSize()) {
            val path = androidx.compose.ui.graphics.Path().apply {
                moveTo(0f, size.height / 2)
                lineTo(size.height / 2, 0f)
                lineTo(size.width - size.height / 2, 0f)
                lineTo(size.width, size.height / 2)
                lineTo(size.width - size.height / 2, size.height)
                lineTo(size.height / 2, size.height)
                close()
            }
            
            drawPath(path, color = backgroundColor)
            drawPath(path, color = borderColor, style = Stroke(width = 3.dp.toPx()))
         }
         
         Row(
             modifier = Modifier.fillMaxSize(),
             verticalAlignment = Alignment.CenterVertically,
             horizontalArrangement = Arrangement.Start
         ) {
             Spacer(modifier = Modifier.width(60.dp))
             Text(
                 text = label,
                 color = if (label == "B") Color(0xFFFF9900) else Color(0xFFFFD700),
                 fontSize = 28.sp,
                 fontWeight = FontWeight.Bold,
                 fontFamily = KinetikaFont
             )
             Spacer(modifier = Modifier.width(32.dp))
             Text(
                 text = text,
                 color = Color.White,
                 fontSize = 24.sp,
                 fontFamily = KinetikaFont
             )
         }
    }
}

@Composable
fun BottomBar(timeMillis: Long) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(80.dp)
            .background(Color.Black)
            .padding(horizontal = 24.dp, vertical = 8.dp)
    ) {
        // Left: QR Code and Text
        Row(
            modifier = Modifier.align(Alignment.CenterStart),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(60.dp)
                    .background(Color.White, RoundedCornerShape(4.dp))
                    .padding(2.dp)
            ) {
                Image(
                    painter = painterResource(id = R.drawable.qr_code),
                    contentDescription = "QR Code",
                    modifier = Modifier.fillMaxSize()
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = "adscreen.az",
                    color = Color.White,
                    fontSize = 18.sp,
                    fontFamily = KinetikaFont,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "+994 51 504 23 23",
                    color = Color.White,
                    fontSize = 18.sp,
                    fontFamily = KinetikaFont,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        // Center: Logos
        Row(
            modifier = Modifier.align(Alignment.Center),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Image(
                painter = painterResource(id = R.drawable.adscreen_logo_new),
                contentDescription = "Adscreen Logo",
                modifier = Modifier.height(24.dp),
                contentScale = ContentScale.Fit
            )

            Spacer(modifier = Modifier.width(24.dp))

            Box(
                modifier = Modifier
                    .width(1.dp)
                    .height(30.dp)
                    .background(Color.White)
            )

            Spacer(modifier = Modifier.width(24.dp))

            Image(
                painter = painterResource(id = R.drawable.mastercard_logo),
                contentDescription = "Mastercard Logo",
                modifier = Modifier.height(30.dp),
                contentScale = ContentScale.Fit
            )
        }

        // Right: Timer
        Box(
            modifier = Modifier.align(Alignment.CenterEnd)
        ) {
            TimerWidget(timeMillis)
        }
    }
}

@Composable
fun TimerWidget(timeMillis: Long) {
    val seconds = timeMillis / 1000
    val formattedTime = remember(seconds) {
        val min = seconds / 60
        val sec = seconds % 60
        String.format("%02d:%02d", min, sec)
    }

    // Smooth progress 0-1 over 60 seconds
    val progress = (timeMillis % 60000) / 60000f

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.size(56.dp)
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val strokeWidth = 5.dp.toPx()
            val radius = size.minDimension / 2 - strokeWidth / 2

            // Background Circle
            drawCircle(
                color = Color(0xFF333333),
                radius = radius,
                style = Stroke(width = strokeWidth)
            )

            // Gradient Arc
            rotate(-90f) {
                drawArc(
                    brush = Brush.sweepGradient(
                        colors = listOf(
                            Color(0xFF6200EA), // Purple
                            Color(0xFFFF9900)  // Orange
                        )
                    ),
                    startAngle = 0f,
                    sweepAngle = 360f * progress,
                    useCenter = false,
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                )
            }
        }

        Text(
            text = formattedTime,
            color = Color.White,
            fontSize = 16.sp,
            fontFamily = KinetikaFont,
            fontWeight = FontWeight.Bold
        )
    }
}
