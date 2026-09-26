library(extrafont)

loadfonts(device = "win", quiet = TRUE)
#if ("Leelawadee" %in% fonts()) {
#   
# } else {
#   font_import(pattern = 'Leel')
# }

### Variables to use outside of plots ###
planitWhite <- "FFFFFF"
planitLightGrey <- "#ECECEC"
planitGrey <- "#7d7d7d"
planitDarkGrey <- "#444444"
planitBlack <- "#000000"
planitBlue <- "#1414FF"
planitOrange <- "#FF6432"
planitPurple <- "#8A3C97"
backgroundBlack <- "#000000"
backgroundWhite <- "#FBFCFC"
passedGreen <- "#2e8b57"
failedRed <- "#ff2600"



# theme_planit <- function(legendPosition = legendPosition, background = background) {
#   
#   
#   ### Colour variables for current Planit branding defined as hexadecimal codes ###
#   planitWhite <- "FFFFFF"
#   planitLightGrey <- "#ECECEC"
#   planitGrey <- "#7d7d7d"
#   planitDarkGrey <- "#444444"
#   planitBlack <- "#000000"
#   planitBlue <- "#1414FF"
#   planitOrange <- "#FF6432"
#   planitPurple <- "#8A3C97"
#   backgroundBlack <- "#000000"
#   backgroundWhite <- "#FBFCFC"
#   passedGreen <- "#2e8b57"
#   failedRed <- "#ff2600"
#   
#   if(background == "dark"){
#     background_colour <- backgroundBlack
#   }else if(background == "light"){
#     background_colour <- backgroundWhite
#   }
#   
#   
#   ### defines the font to be used throughout ###
#   font <- "Leelawadee UI"
# 
#   
#   ### Defining a theme for ggplot2 using the variables above ###
#   ggplot2::theme(
#     
#     
#     ################
#     ###          ###
#     ###   TEXT   ###
#     ###          ###
#     ################
#     
#     ### This sets the font, size, type and colour of text for the chart's title ###
#     plot.title = ggplot2::element_text(family = font, size = 24, color=planitBlack),
#     
#     ### This sets the font, size, type and colour of text for the chart's subtitle, as well as setting a margin between the title and the subtitle ###
#     plot.subtitle = ggplot2::element_text(family = font, size = 18, colour = planitDarkGrey, margin = ggplot2::margin(9,0,9,0)),
#     plot.caption = ggplot2::element_blank(),
#     
#     
#     
#     
#     ##################
#     ###            ###
#     ###   LEGEND   ###
#     ###            ###
#     ##################
#     
#     ### This sets the position and alignment of the legend, removes a title and background for it and sets the requirements for any text within the legend. The legend may often need some more manual tweaking when it comes to its exact position based on the plot coordinates ###
#     legend.position = legendPosition,
#     legend.text.align = 0,
#     legend.background = ggplot2::element_blank(),
#     legend.title = ggplot2::element_blank(),
#     legend.key = ggplot2::element_blank(),
#     legend.text = ggplot2::element_text(family = font, size = 10, color = planitBlack),
#     
#     
#     
#     
#     ################
#     ###          ###
#     ###   AXIS   ###
#     ###          ###
#     ################
#     
#     ### This sets the text font, size and colour for the axis, as well as setting the margins and removing any lines and ticks ###
#     axis.title = ggplot2::element_text(family = font, size = 12, color = planitBlack),
#     axis.text = ggplot2::element_text(family = font, size = 14, color = planitBlack),
#     axis.title.y.left = ggplot2::element_text(family = font, size = 12, color = planitBlack, margin = ggplot2::margin(r = 50)),
#     axis.text.x = ggplot2::element_text(margin = ggplot2::margin(5, b = 20), size = 14, family = font, colour = planitBlack),
#     axis.text.y = ggplot2::element_text(margin = ggplot2::margin(10, b = 20), size = 14, family = font, colour = planitBlack),
#     axis.ticks = ggplot2::element_blank(),
#     axis.line = ggplot2::element_blank(),
#     
# 
#     
#     
#     ######################
#     ###                ###
#     ###   GRID LINES   ###
#     ###                ###
#     ######################    
#     
#     ### This removes all minor gridlines and adds major y gridlines ###
#     panel.grid.minor = ggplot2::element_blank(),
#     panel.grid.major.y = ggplot2::element_line(color = planitDarkGrey, linetype = "dotted", size = 0.5),
#     panel.grid.major.x = ggplot2::element_blank(),
#     
#     
#     ### Change plot background ###
#     plot.background = ggplot2::element_rect(fill = background_colour),
#     plot.margin = margin(10, 10, 10, 100),
#     
#     ### This sets the panel background as blank, removing the standard grey ggplot background colour from the plot ###
#     panel.background = ggplot2::element_rect(fill = background_colour),
#     panel.border = element_rect(colour = planitBlack, fill = NA, size = 0.5),
#     
#     ### This sets the panel background for facet-wrapped plots to white, removing the standard grey ggplot background colour and sets the title size of the facet-wrap title to font size 22 ###
#     strip.background = element_rect(fill = planitBlack, colour = planitWhite),
#     strip.text = ggplot2::element_text(family = font, size = 13, hjust = 0, colour = planitWhite)
    
  )
}